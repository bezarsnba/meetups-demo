#!/usr/bin/env bash
set -euo pipefail

# Provisiona o ambiente de demo: cluster k3d + Kyverno + ArgoCD + Policy Reporter.
# Pressupõe k3d, kubectl e helm instalados.

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CTX=k3d-tdc-kyverno

"${REPO_ROOT}/scripts/setup-k3d.sh"

# O kubeconfig costuma ser compartilhado com outros clusters/talks no mesmo
# host — o current-context pode trocar sozinho entre uma etapa e outra deste
# script se outra sessão mexer nele em paralelo. Por isso todo comando abaixo
# usa --context="$CTX" explícito em vez de depender do current-context.

echo "==> Instalando Kyverno"
helm repo add kyverno https://kyverno.github.io/kyverno/ >/dev/null
helm repo update >/dev/null
# reg.kyverno.io tem se mostrado inacessível/flaky em alguns ambientes locais;
# ghcr.io serve as mesmas imagens e responde de forma confiável.
helm upgrade --install kyverno kyverno/kyverno \
  --kube-context "$CTX" \
  --namespace kyverno --create-namespace \
  --set global.image.registry=ghcr.io \
  --wait

echo "==> Validando o control plane do Kyverno antes de aplicar as políticas"
kubectl --context="$CTX" -n kyverno rollout status deployment/kyverno-admission-controller

echo "==> Aplicando as políticas de demo"
kubectl --context="$CTX" apply -f "${REPO_ROOT}/policies/"

echo "==> Instalando ArgoCD"
kubectl --context="$CTX" create namespace argocd --dry-run=client -o yaml | kubectl --context="$CTX" apply -f -
# --server-side: os CRDs do ArgoCD (applicationsets.argoproj.io) excedem o limite
# de tamanho da annotation last-applied-configuration usada pelo apply padrão.
kubectl --context="$CTX" apply -n argocd --server-side --force-conflicts \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl --context="$CTX" -n argocd rollout status deployment/argocd-server

echo "==> Registrando a Application de demo no ArgoCD"
kubectl --context="$CTX" apply -f "${REPO_ROOT}/gitops/argocd/application.yaml"

echo "==> Instalando Policy Reporter (dashboard de PolicyReport/ClusterPolicyReport)"
helm repo add policy-reporter https://kyverno.github.io/policy-reporter >/dev/null
helm repo update policy-reporter >/dev/null
helm upgrade --install policy-reporter policy-reporter/policy-reporter \
  --kube-context "$CTX" \
  --namespace policy-reporter --create-namespace \
  --set ui.enabled=true \
  --set kyverno-plugin.enabled=true \
  --wait

cat <<'EOF'

==> Ambiente pronto.

Acesso ao ArgoCD UI:
  kubectl --context=k3d-tdc-kyverno -n argocd port-forward svc/argocd-server 8080:443
  usuário: admin
  senha:   kubectl --context=k3d-tdc-kyverno -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d

Acesso ao Policy Reporter UI:
  kubectl --context=k3d-tdc-kyverno -n policy-reporter port-forward service/policy-reporter-ui 8082:8080
  Abra: http://localhost:8082/

Ver demo.md para o roteiro de apresentação.
EOF
