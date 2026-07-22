# Infraestrutura GKE (Terraform) — só provisionamento

Este guia só sobe a infra e instala os serviços. Ele **não** aplica os
manifests da demo (Ingress, Gateway, HTTPRoutes, mesh) — isso fica pro
`demo.md` na raiz do repo, rodado com [`demosh`](https://github.com/BuoyantIO/demosh)
no dia da talk. A ideia é deixar tudo pronto aqui com antecedência, e no
palco só rodar o `demo.md`.

## 1. Cluster

```bash
cd terraform/gke
terraform init
terraform apply -var project_id=SEU_PROJETO
$(terraform output -raw get_credentials)   # configura o kubectl
```

Cluster GKE Standard, 3x `e2-standard-2` em São Paulo (`southamerica-east1-a`).
Standard, não Autopilot — o init container do Linkerd precisa de
`NET_ADMIN`/`NET_RAW`, o que dá atrito no Autopilot.

A Gateway API nativa do GKE fica **desabilitada** de propósito
(`gateway_api_config { channel = "CHANNEL_DISABLED" }`) — os CRDs são
instalados pelo chart do Envoy Gateway, e o gateway precisa ser um pod para
entrar no mesh do Linkerd (o controller nativo `gke-l7` roda fora do cluster,
não dá pra meshar).

Cada Service `LoadBalancer` (`ingress-nginx` e `envoy-gateway`) ganha seu
**próprio IP público** via GCP Network LB automaticamente — sem o conflito de
porta que existe no ensaio local (ver [`local.md`](./local.md), que usa
MetalLB pra replicar esse mesmo comportamento).

O Terraform também reserva **2 IPs estáticos regionais** (`google_compute_address`,
mesma região do cluster), um para o `ingress-nginx` e outro para o Envoy
Gateway — sem isso, cada `helm upgrade` ou recriação de Service pode trocar o
IP, invalidando o QR code e a URL sslip.io preparados com antecedência:

```bash
terraform output -raw ingress_ip    # IP fixo do Ato 1
terraform output -raw gateway_ip    # IP fixo do Ato 2/3 — o que vai no QR code
```

Com o IP do Gateway em mãos, já dá pra montar a URL amigável desde agora,
sem esperar o cluster: `http://podinfo.<gateway_ip-com-tracinho>.sslip.io`
(ex: `34.39.197.16` → `podinfo.34-39-197-16.sslip.io`) — resolve sozinho,
sem precisar configurar DNS.

## 2. Serviços (Helm)

Atalho — instala tudo de uma vez (ingress-nginx, Envoy Gateway + EnvoyProxy
com IP fixo, Linkerd, app):

```bash
./scripts/install-components.sh
```

Ou passo a passo, pra entender cada etapa (ordem importa: o Linkerd exige os
CRDs da Gateway API, que chegam com o Envoy Gateway):

```bash
# 2.1 — ingress-nginx (só para o Ato 1, o "antes") — preso no IP reservado
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
  -n ingress-nginx --create-namespace \
  --set controller.service.type=LoadBalancer \
  --set controller.service.loadBalancerIP=$(terraform -chdir=terraform/gke output -raw ingress_ip)

# 2.2 — Envoy Gateway (instala também os CRDs da Gateway API)
helm upgrade --install eg oci://docker.io/envoyproxy/gateway-helm \
  --version v1.4.1 \
  -n envoy-gateway-system --create-namespace

# 2.2.1 — EnvoyProxy: fixa o IP do Service que o Gateway vai criar.
# Necessário porque, no GKE, `Gateway.spec.addresses` (o campo "oficial" da
# Gateway API) é ignorado pelo Envoy Gateway — ele sobe um IP efêmero mesmo
# assim (https://github.com/envoyproxy/gateway/issues/4335). O caminho que
# funciona de verdade é via EnvoyProxy + infrastructure.parametersRef no
# Gateway (feito em demo.md, no Ato 2 — o Gateway só existe depois disso).
cat <<EOF | kubectl apply -n infra -f -
apiVersion: gateway.envoyproxy.io/v1alpha1
kind: EnvoyProxy
metadata:
  name: envoy-static-ip
spec:
  provider:
    type: Kubernetes
    kubernetes:
      envoyService:
        loadBalancerIP: $(terraform -chdir=terraform/gke output -raw gateway_ip)
EOF

# 2.3 — Linkerd: certificados de identidade (step-cli) + charts
step certificate create root.linkerd.cluster.local ca.crt ca.key \
  --profile root-ca --no-password --insecure
step certificate create identity.linkerd.cluster.local issuer.crt issuer.key \
  --profile intermediate-ca --not-after 8760h --no-password --insecure \
  --ca ca.crt --ca-key ca.key

helm repo add linkerd-edge https://helm.linkerd.io/edge
helm upgrade --install linkerd-crds linkerd-edge/linkerd-crds \
  -n linkerd --create-namespace

# O GKE aloca o CIDR de Services fora das faixas privadas que o Linkerd
# assume por padrão (clusterNetworks) — sem somar essa faixa, `linkerd check`
# falha em "cluster networks contains all services" assim que qualquer
# Service da demo existir (ex: podinfo).
SERVICES_CIDR=$(terraform -chdir=terraform/gke output -raw services_ipv4_cidr)
helm upgrade --install linkerd-control-plane linkerd-edge/linkerd-control-plane \
  -n linkerd \
  --set-file identityTrustAnchorsPEM=ca.crt \
  --set-file identity.issuer.tls.crtPEM=issuer.crt \
  --set-file identity.issuer.tls.keyPEM=issuer.key \
  --set clusterNetworks="10.0.0.0/8\,100.64.0.0/10\,172.16.0.0/12\,192.168.0.0/16\,fd00::/8\,${SERVICES_CIDR}"

# Espere os deployments core (destination/identity/proxy-injector) ficarem
# Ready ANTES de instalar o viz — o webhook do proxy-injector usa
# failurePolicy=Ignore, então se ele não estiver pronto quando o viz for
# instalado, os pods dele sobem SEM sidecar, silenciosamente, sem erro.
kubectl -n linkerd rollout status deployment/linkerd-destination --timeout=180s
kubectl -n linkerd rollout status deployment/linkerd-identity --timeout=180s
kubectl -n linkerd rollout status deployment/linkerd-proxy-injector --timeout=180s
linkerd check   # sanidade antes de seguir

helm upgrade --install linkerd-viz linkerd-edge/linkerd-viz \
  -n linkerd-viz --create-namespace

linkerd check   # sanidade antes de subir no palco

# 2.4 — app da demo
kubectl apply -f app/
```

> Os arquivos `ca.key` / `issuer.key` ficam fora do git (`.gitignore`). Para o
> polimento de TLS público (cert-manager + Let's Encrypt), veja "Backlog" no
> README principal.

Depois disso, o ambiente está pronto. No dia da talk, rode só:

```bash
demosh demo.md
```

(o `demosh` narra e pausa entre os comandos — ver instalação em
[BuoyantIO/demosh](https://github.com/BuoyantIO/demosh#to-install-demosh)).
O [roteiro de palco](../README.md#roteiro-de-palco) no README principal tem
o mesmo conteúdo em texto corrido, caso prefira rodar manualmente.

## Custo e limpeza

~US$ 0,30/h de cluster + ~US$ 0,03/h por LoadBalancer + uma taxa pequena por
IP estático reservado (cobra menos ainda enquanto o IP está em uso por um
LoadBalancer ativo). Depois da palestra, **desinstale os Helm releases antes
do `destroy`** — o GCP não libera um IP estático enquanto ele estiver preso a
um forwarding rule ativo, e o `terraform destroy` vai falhar tentando
remover `google_compute_address` nesse estado:

```bash
helm uninstall ingress-nginx -n ingress-nginx
helm uninstall eg -n envoy-gateway-system   # também derruba o Service do Gateway
cd terraform/gke && terraform destroy -var project_id=SEU_PROJETO
```
