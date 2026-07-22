#!/usr/bin/env bash
set -euo pipefail

# Instala os serviços da demo via Helm/kubectl no cluster GKE já provisionado
# pelo Terraform (terraform/gke). Só GKE — o ensaio local (docs/local.md)
# usa MetalLB e não precisa de IP estático.
#
# Pré-requisito: `kubectl` já apontando pro cluster e `terraform apply` já
# rodado em terraform/gke (as duas static IPs precisam existir).
#
# Uso: ./scripts/install-components.sh

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF_DIR="$REPO_ROOT/terraform/gke"

INGRESS_IP=$(terraform -chdir="$TF_DIR" output -raw ingress_ip)
GATEWAY_IP=$(terraform -chdir="$TF_DIR" output -raw gateway_ip)
SERVICES_CIDR=$(terraform -chdir="$TF_DIR" output -raw services_ipv4_cidr)

echo "==> ingress_ip=$INGRESS_IP  gateway_ip=$GATEWAY_IP  services_cidr=$SERVICES_CIDR"

# O GKE aloca o CIDR de Services fora das faixas privadas que o Linkerd
# assume por padrão (clusterNetworks) — sem isso, `linkerd check` falha em
# "cluster networks contains all services" assim que qualquer Service da
# demo existir (ex: podinfo).
LINKERD_CLUSTER_NETWORKS="10.0.0.0/8\,100.64.0.0/10\,172.16.0.0/12\,192.168.0.0/16\,fd00::/8\,${SERVICES_CIDR}"

echo "==> 1/4 ingress-nginx (Ato 1)"
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx >/dev/null
helm repo update ingress-nginx >/dev/null
helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
  -n ingress-nginx --create-namespace \
  --set controller.service.type=LoadBalancer \
  --set controller.service.loadBalancerIP="$INGRESS_IP"

kubectl -n ingress-nginx rollout status deployment/ingress-nginx-controller --timeout=180s

echo "    aguardando o GCP atribuir o IP estático ao Service (pode levar 1-3min)..."
for i in $(seq 1 30); do
  ACTUAL_IP=$(kubectl -n ingress-nginx get svc ingress-nginx-controller \
    -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)
  [[ "$ACTUAL_IP" == "$INGRESS_IP" ]] && break
  sleep 10
done
if [[ "$ACTUAL_IP" != "$INGRESS_IP" ]]; then
  echo "ERRO: Service ingress-nginx-controller não ficou com o IP $INGRESS_IP (atual: '${ACTUAL_IP:-<vazio>}')" >&2
  exit 1
fi
echo "    ok — IP $ACTUAL_IP confirmado"

echo "==> 2/4 Envoy Gateway (CRDs da Gateway API + controller)"
helm upgrade --install eg oci://docker.io/envoyproxy/gateway-helm \
  --version v1.4.1 \
  -n envoy-gateway-system --create-namespace

kubectl -n envoy-gateway-system rollout status deployment/envoy-gateway --timeout=180s

echo "==> 2.1/4 namespace infra + EnvoyProxy (fixa o IP do Gateway)"
kubectl apply -f "$REPO_ROOT/ato2-gateway/namespace.yaml"
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
        loadBalancerIP: $GATEWAY_IP
EOF

echo "==> 3/4 Linkerd (certificados + charts)"
if [[ ! -f "$REPO_ROOT/ca.crt" ]]; then
  step certificate create root.linkerd.cluster.local \
    "$REPO_ROOT/ca.crt" "$REPO_ROOT/ca.key" \
    --profile root-ca --no-password --insecure
  step certificate create identity.linkerd.cluster.local \
    "$REPO_ROOT/issuer.crt" "$REPO_ROOT/issuer.key" \
    --profile intermediate-ca --not-after 8760h --no-password --insecure \
    --ca "$REPO_ROOT/ca.crt" --ca-key "$REPO_ROOT/ca.key"
else
  echo "    (certificados já existem em $REPO_ROOT, reaproveitando)"
fi

helm repo add linkerd-edge https://helm.linkerd.io/edge >/dev/null
helm repo update linkerd-edge >/dev/null
helm upgrade --install linkerd-crds linkerd-edge/linkerd-crds \
  -n linkerd --create-namespace
helm upgrade --install linkerd-control-plane linkerd-edge/linkerd-control-plane \
  -n linkerd \
  --set-file identityTrustAnchorsPEM="$REPO_ROOT/ca.crt" \
  --set-file identity.issuer.tls.crtPEM="$REPO_ROOT/issuer.crt" \
  --set-file identity.issuer.tls.keyPEM="$REPO_ROOT/issuer.key" \
  --set clusterNetworks="$LINKERD_CLUSTER_NETWORKS"

echo "==> 3.1/4 aguardando control plane ficar pronto antes de seguir"
# Crítico: o webhook do proxy-injector usa failurePolicy=Ignore — se ele não
# estiver pronto quando um pod anotado (ex: linkerd-viz) for criado, o pod
# sobe SEM sidecar, silenciosamente, sem erro nenhum. `linkerd check` inclui
# uma chamada real ao webhook, então só prossegue depois que ele responder.
kubectl -n linkerd rollout status deployment/linkerd-destination --timeout=180s
kubectl -n linkerd rollout status deployment/linkerd-identity --timeout=180s
kubectl -n linkerd rollout status deployment/linkerd-proxy-injector --timeout=180s
linkerd check

echo "==> 3.2/4 linkerd-viz (agora que o control plane está confirmado up)"
helm upgrade --install linkerd-viz linkerd-edge/linkerd-viz \
  -n linkerd-viz --create-namespace
for d in web metrics-api tap tap-injector prometheus; do
  kubectl -n linkerd-viz rollout status "deployment/$d" --timeout=120s
done
linkerd viz check

echo "==> 4/4 app da demo (podinfo v1/v2)"
kubectl apply -f "$REPO_ROOT/app/"
kubectl -n apps rollout status deployment/podinfo-v1 --timeout=120s
kubectl -n apps rollout status deployment/podinfo-v2 --timeout=120s

echo "==> pronto. Ambiente instalado — rode 'demosh demo.md' no dia da talk."
