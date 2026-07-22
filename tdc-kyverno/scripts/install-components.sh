#!/usr/bin/env bash
set -euo pipefail

# Provisiona o ambiente de demo: cluster k3d + Kyverno + ArgoCD.
# Pressupõe k3d, kubectl e helm instalados.

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "==> Criando cluster k3d (tdc-kyverno)"
k3d cluster create --config "${REPO_ROOT}/local/k3d.yaml"

echo "==> Instalando Kyverno"
helm repo add kyverno https://kyverno.github.io/kyverno/ >/dev/null
helm repo update >/dev/null
# reg.kyverno.io tem se mostrado inacessível/flaky em alguns ambientes locais;
# ghcr.io serve as mesmas imagens e responde de forma confiável.
helm upgrade --install kyverno kyverno/kyverno \
  --namespace kyverno --create-namespace \
  --set global.image.registry=ghcr.io \
  --wait

echo "==> Validando o control plane do Kyverno antes de aplicar as políticas"
kubectl -n kyverno rollout status deployment/kyverno-admission-controller

echo "==> Aplicando as políticas de demo"
kubectl apply -f "${REPO_ROOT}/policies/"

echo "==> Instalando ArgoCD"
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
# --server-side: os CRDs do ArgoCD (applicationsets.argoproj.io) excedem o limite
# de tamanho da annotation last-applied-configuration usada pelo apply padrão.
kubectl apply -n argocd --server-side --force-conflicts \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl -n argocd rollout status deployment/argocd-server

echo "==> Registrando a Application de demo no ArgoCD"
kubectl apply -f "${REPO_ROOT}/gitops/argocd/application.yaml"

cat <<'EOF'

==> Ambiente pronto.

Acesso ao ArgoCD UI:
  kubectl -n argocd port-forward svc/argocd-server 8080:443
  usuário: admin
  senha:   kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d

Ver demo.md para o roteiro de apresentação.
EOF
