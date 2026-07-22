# Ensaio local (k3d)

Ambiente local para ensaiar a demo antes do dia da palestra. Usamos MetalLB no
lugar do `servicelb` (klipper) padrão do k3s, para que os Services
`LoadBalancer` ganhem IP de verdade — o mesmo comportamento do GKE
(ver [`gke.md`](./gke.md)).

## Pré-requisito (uma vez por máquina)

k3s consome muitos watchers de inotify — com os defaults do kernel o cluster
**trava na criação** ("too many open files" no containerd):

```bash
sudo sysctl fs.inotify.max_user_instances=1024 fs.inotify.max_user_watches=1048576
echo -e "fs.inotify.max_user_instances=1024\nfs.inotify.max_user_watches=1048576" \
  | sudo tee /etc/sysctl.d/99-inotify.conf
```

## 1. Cluster

```bash
k3d cluster create --config local/k3d.yaml
```

O `local/k3d.yaml` desabilita o Traefik embutido (conflitaria com o Envoy
Gateway na porta 80 e na Gateway API) e o `servicelb` (klipper) — usamos o
MetalLB no lugar, pelo motivo abaixo.

### Por que MetalLB, e não o klipper

O klipper não aloca IP de verdade: ele faz *bind* da porta do Service em
**todos os nós** via hostPort. Este repo sobe dois Services `LoadBalancer` na
porta 80 ao mesmo tempo (`ingress-nginx` e `envoy-gateway`) — com o klipper,
os dois competem pela mesma hostPort e um deles trava em `Pending`, deixando
o Gateway em `AddressNotAssigned`. O MetalLB aloca um IP virtual por Service
(anunciado via ARP/L2, sem bind de porta), então os dois convivem sem
conflito — os mesmos dois IPs distintos que você teria no GKE.

## 2. MetalLB

```bash
helm repo add metallb https://metallb.github.io/metallb
helm upgrade --install metallb metallb/metallb -n metallb-system --create-namespace
kubectl rollout status deployment -n metallb-system metallb-controller

SUBNET=$(docker network inspect k3d-tdc-gatewayapi -f '{{ (index .IPAM.Config 0).Subnet }}')
POOL_BASE=$(echo "$SUBNET" | cut -d. -f1-2)   # ex: 172.22

cat <<EOF | kubectl apply -f -
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: demo-pool
  namespace: metallb-system
spec:
  addresses:
    - ${POOL_BASE}.1.200-${POOL_BASE}.1.220
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: demo-l2
  namespace: metallb-system
EOF
```

## 3. Serviços (Helm)

Ordem importa: o Linkerd exige os CRDs da Gateway API, que chegam com o Envoy Gateway.

```bash
# 3.1 — ingress-nginx (só para o Ato 1, o "antes")
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
  -n ingress-nginx --create-namespace \
  --set controller.service.type=LoadBalancer

# 3.2 — Envoy Gateway (instala também os CRDs da Gateway API)
helm upgrade --install eg oci://docker.io/envoyproxy/gateway-helm \
  --version v1.4.1 \
  -n envoy-gateway-system --create-namespace

# 3.3 — Linkerd: certificados de identidade (step-cli) + charts
step certificate create root.linkerd.cluster.local ca.crt ca.key \
  --profile root-ca --no-password --insecure
step certificate create identity.linkerd.cluster.local issuer.crt issuer.key \
  --profile intermediate-ca --not-after 8760h --no-password --insecure \
  --ca ca.crt --ca-key ca.key

helm repo add linkerd-edge https://helm.linkerd.io/edge
helm upgrade --install linkerd-crds linkerd-edge/linkerd-crds \
  -n linkerd --create-namespace
helm upgrade --install linkerd-control-plane linkerd-edge/linkerd-control-plane \
  -n linkerd \
  --set-file identityTrustAnchorsPEM=ca.crt \
  --set-file identity.issuer.tls.crtPEM=issuer.crt \
  --set-file identity.issuer.tls.keyPEM=issuer.key
helm upgrade --install linkerd-viz linkerd-edge/linkerd-viz \
  -n linkerd-viz --create-namespace

linkerd check   # sanidade antes de subir no palco

# 3.4 — app da demo
kubectl apply -f app/
```

> Os arquivos `ca.key` / `issuer.key` ficam fora do git (`.gitignore`).

Depois disso, siga o [roteiro de palco](../README.md#roteiro-de-palco) no
README principal — é idêntico ao do GKE.

## Limpeza

```bash
k3d cluster delete tdc-gatewayapi
```
