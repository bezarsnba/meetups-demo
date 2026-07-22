#!/usr/bin/env bash
set -euo pipefail

# Imprime a URL pública da demo. Uso: ./scripts/get-url.sh [ingress|gateway]

TARGET="${1:-gateway}"

case "$TARGET" in
  ingress)
    IP=$(kubectl get svc -n ingress-nginx ingress-nginx-controller \
      -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
    PORT=$(kubectl get svc -n ingress-nginx ingress-nginx-controller \
      -o jsonpath='{.spec.ports[?(@.name=="http")].port}')
    ;;
  gateway)
    IP=$(kubectl get gateway -n infra demo-gateway \
      -o jsonpath='{.status.addresses[0].value}')
    PORT=$(kubectl get gateway -n infra demo-gateway \
      -o jsonpath='{.spec.listeners[?(@.name=="http")].port}')
    ;;
  *)
    echo "uso: $0 [ingress|gateway]" >&2
    exit 1
    ;;
esac

if [[ -z "$IP" ]]; then
  echo "IP ainda não atribuído — aguarde o LoadBalancer e tente de novo." >&2
  exit 1
fi

SUFFIX=""
[[ "$PORT" != "80" ]] && SUFFIX=":$PORT"
echo "http://$IP$SUFFIX"
echo "http://podinfo.${IP//./-}.sslip.io$SUFFIX"
