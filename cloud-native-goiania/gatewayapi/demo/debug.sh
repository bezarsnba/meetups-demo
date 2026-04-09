#!/bin/bash

# Script de Debug para Gateway API Demo

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

header() {
    echo -e "\n${BLUE}=== $1 ===${NC}\n"
}

header "1. STATUS DO CLUSTER"
kubectl cluster-info
kubectl get nodes -o wide

header "2. STATUS DO MetalLB"
kubectl get pods -n metallb-system
kubectl get svc -n metallb-system
kubectl get ipaddresspool -n metallb-system 2>/dev/null || echo "Sem IPAddressPool"

header "3. STATUS DO TRAEFIK"
kubectl get pods -n traefik -o wide
kubectl get svc -n traefik -o wide
kubectl get gatewayclasses

header "4. LOGS DO TRAEFIK (últimas 20 linhas)"
kubectl logs -n traefik -l app.kubernetes.io/name=traefik --tail=20 || echo "Sem logs"

header "5. STATUS DO INGRESS-NGINX"
kubectl get pods -n ingress-nginx -o wide
kubectl get svc -n ingress-nginx -o wide
kubectl get ingressclass

header "6. STATUS DO GATEWAY"
kubectl get gateway -n demo-app -o wide
kubectl describe gateway/my-gateway -n demo-app 2>/dev/null || echo "Gateway não encontrado"

header "7. STATUS DO APP (demo-app)"
kubectl get all -n demo-app -o wide

header "8. EVENTOS DO NAMESPACE demo-app"
kubectl get events -n demo-app --sort-by='.lastTimestamp' | tail -20

header "9. HTTPRoutes"
kubectl get httproutes -n demo-app -o wide
kubectl describe httproute -n demo-app 2>/dev/null || echo "Sem HTTPRoutes"

header "10. INGRESS"
kubectl get ingress -n demo-app -o wide
kubectl describe ingress -n demo-app 2>/dev/null || echo "Sem Ingress"

header "11. STATUS DAS REQUISIÇÕES"
echo "Testando conectividade..."

# Get IPs
TRAEFIK_IP=$(kubectl get svc traefik -n traefik -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)
NGINX_IP=$(kubectl get svc ingress-nginx -n ingress-nginx -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)

if [ -z "$TRAEFIK_IP" ]; then
    echo -e "${YELLOW}Traefik IP: <pending>${NC}"
else
    echo -e "${GREEN}Traefik IP: $TRAEFIK_IP${NC}"
    echo "Testando: curl -i http://$TRAEFIK_IP -H 'Host: app.demo'"
    curl -i http://$TRAEFIK_IP -H 'Host: app.demo' --max-time 5 2>/dev/null || echo "Conexão recusada"
fi

if [ -z "$NGINX_IP" ]; then
    echo -e "${YELLOW}Nginx-ingress IP: <pending>${NC}"
else
    echo -e "${GREEN}Nginx-ingress IP: $NGINX_IP${NC}"
    echo "Testando: curl -i http://$NGINX_IP -H 'Host: app.demo'"
    curl -i http://$NGINX_IP -H 'Host: app.demo' --max-time 5 2>/dev/null || echo "Conexão recusada"
fi

header "12. CRDs GATEWAY API"
kubectl get crds | grep gateway.networking

echo -e "\n${GREEN}Debug completo!${NC}\n"
