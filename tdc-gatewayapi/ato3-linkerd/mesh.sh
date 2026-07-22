#!/usr/bin/env bash
set -euo pipefail

# ATO 3 — coloca app E gateway no mesh do Linkerd.
# Meshar o Envoy Gateway é o ponto-chave da talk: o mTLS passa a cobrir
# o caminho inteiro (gateway → app), não só o tráfego entre serviços.

kubectl annotate namespace apps linkerd.io/inject=enabled --overwrite
kubectl annotate namespace envoy-gateway-system linkerd.io/inject=enabled --overwrite

kubectl rollout restart deployment -n apps
kubectl rollout restart deployment -n envoy-gateway-system

kubectl rollout status deployment -n apps --timeout=120s
kubectl rollout status deployment -n envoy-gateway-system --timeout=120s

echo ""
echo "✅ Mesh ativo. Para provar o mTLS ao vivo:"
echo "   linkerd viz edges deployment -n apps    # coluna SECURED"
echo "   linkerd viz stat deploy -n apps         # golden metrics"
echo "   linkerd viz dashboard                   # RPS da plateia em tempo real"
