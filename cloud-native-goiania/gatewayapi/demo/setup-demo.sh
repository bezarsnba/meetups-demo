#!/bin/bash

# Não parar no primeiro erro
set +e

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Funções auxiliares
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[!]${NC} $1"
}

log_error() {
    echo -e "${RED}[✗]${NC} $1"
}

check_command() {
    if ! command -v $1 &> /dev/null; then
        log_error "$1 não encontrado. Instale e tente novamente."
        exit 1
    fi
}

# Verificações pré-requisitos
log_info "Verificando pré-requisitos..."
check_command kubectl
check_command helm
check_command helmfile

log_success "Pré-requisitos OK"
echo ""

# Verificar conexão com cluster
log_info "Verificando conexão com cluster Kubernetes..."
if ! kubectl cluster-info &>/dev/null; then
    log_error "Não foi possível conectar ao cluster Kubernetes"
    log_error "Certifique-se de que o cluster k3d está rodando"
    exit 1
fi

log_success "Cluster Kubernetes acessível"
echo ""

# PASSO 1: Instalar Gateway API CRDs
log_info "=========================================="
log_info "PASSO 1: Instalar Gateway API v1.4.0"
log_info "=========================================="

log_info "Instalando CRDs do Gateway API..."
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.4.0/standard-install.yaml

# Aguardar CRDs estarem disponíveis
sleep 5
log_info "Aguardando CRDs ficarem disponíveis..."
kubectl wait --for condition=Established crd/gatewayclasses.gateway.networking.k8s.io --timeout=60s

log_success "Gateway API CRDs instalados"
echo ""

# Validar instalação
log_info "Verificando GatewayClasses..."
kubectl get gatewayclasses || log_warn "Nenhum GatewayClass disponível ainda (será criado pelo Traefik)"
echo ""

# PASSO 2: Instalar Traefik v3 via Helmfile
log_info "=========================================="
log_info "PASSO 2: Instalar Traefik v3 via Helmfile"
log_info "=========================================="

log_info "Sincronizando Traefik via Helmfile..."
helmfile -f helmfile/traefik/helmfile.yaml sync

log_info "Aguardando Traefik estar pronto..."
kubectl wait --for=condition=Ready pod \
    -l app.kubernetes.io/name=traefik \
    -n traefik \
    --timeout=300s 2>/dev/null || log_warn "Traefik ainda não pronto (pode estar iniciando)"

log_success "Traefik v3 instalado"
echo ""

# Validar
log_info "Verificando GatewayClass do Traefik..."
kubectl get gatewayclasses || log_warn "GatewayClass ainda não visível"
echo ""

# PASSO 2.5: Instalar Ingress-Nginx (cria IngressClass 'nginx' necessária para o provider kubernetesIngressNginx do Traefik)
log_info "=========================================="
log_info "PASSO 2.5: Instalar Ingress-Nginx"
log_info "=========================================="

log_info "Sincronizando Ingress-Nginx via Helmfile..."
helmfile -f helmfile/nginx-ingress/helmfile.yaml sync

log_info "Aguardando Ingress-Nginx estar pronto..."
kubectl wait --for=condition=Ready pod \
    -l app.kubernetes.io/name=ingress-nginx \
    -n ingress-nginx \
    --timeout=300s 2>/dev/null || log_warn "Ingress-Nginx ainda não pronto (pode estar iniciando)"

log_info "Verificando IngressClass nginx..."
kubectl get ingressclass nginx || log_warn "IngressClass nginx não encontrada"

log_success "Ingress-Nginx instalado"
echo ""


# PASSO 4: Deploy Podinfo Simplificado
log_info "=========================================="
log_info "PASSO 5: Deploy Podinfo (app única)"
log_info "=========================================="

log_info "Deploying podinfo com namespace e app..."
kubectl apply -f manifests/50-simple-app.yaml

sleep 3

log_info "Criando Ingress (método legacy)..."
kubectl apply -f manifests/51-ingress-legacy.yaml

log_success "Podinfo e rotas deployados"
echo ""


# PASSO 3: Provisionar Gateway
log_info "=========================================="
log_info "PASSO 4: Provisionar Gateway"
log_info "=========================================="

log_info "Criando Gateway..."
kubectl apply -f manifests/01-gateway.yaml

log_info "Aguardando Gateway ficar pronto (timeout: 5 minutos)..."
kubectl wait --for=condition=Ready gateway/my-gateway \
    -n demo-app \
    --timeout=300s 2>/dev/null || {
    log_warn "Gateway ainda não pronto após 5 minutos. Verificando status..."
    kubectl describe gateway/my-gateway -n demo-app || true
    kubectl get gateway -n demo-app -o wide || true
}

log_success "Gateway provisionado"
echo ""
# PASSO 5: Validações Finais
log_info "=========================================="
log_info "PASSO 5: Validações Finais"
log_info "=========================================="

log_info "Verificando recursos..."

echo ""
log_info "Namespaces criados:"
kubectl get ns -L app

echo ""
log_info "Gateways (namespace demo-app):"
kubectl get gateways -n demo-app

echo ""
log_info "HTTPRoutes (namespace demo-app):"
kubectl get httproutes -n demo-app

echo ""
log_info "Ingress (namespace demo-app):"
kubectl get ingress -n demo-app

echo ""
log_info "Deployments (namespace demo-app):"
kubectl get deployments -n demo-app

echo ""
log_success "Setup completo! 🎉"
echo ""

# Informações de acesso
log_info "Próximos passos:"
echo ""
log_info "1. Verificar LoadBalancer IPs atribuídos:"
echo "   kubectl get svc traefik -n traefik"
echo "   kubectl get svc ingress-nginx -n ingress-nginx"
echo ""

log_info "2. Obter IPs para testar:"
echo "   TRAEFIK_IP=\$(kubectl get svc traefik -n traefik -o jsonpath='{.status.loadBalancer.ingress[0].ip}')"
echo "   NGINX_IP=\$(kubectl get svc ingress-nginx-controller -n ingress-nginx -o jsonpath='{.status.loadBalancer.ingress[0].ip}')"
echo "   echo \"Traefik: \$TRAEFIK_IP\""
echo "   echo \"Nginx-ingress: \$NGINX_IP\""
echo ""

log_info "3. Testar via curl (com Host header):"
echo "   curl -i http://\$TRAEFIK_IP -H 'Host: app.com'"
echo "   curl -i http://\$NGINX_IP -H 'Host: app.com'"
echo ""

log_info "4. Verificar recursos escalonáveis:"
echo "   kubectl get httproutes -n demo-app"
echo "   kubectl get ingress -n demo-app"
echo "   kubectl get gatewayclasses"
echo ""

log_info "5. Visualizar logs:"
echo "   kubectl logs -n traefik -l app.kubernetes.io/name=traefik -f"
echo "   kubectl logs -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx -f"
echo ""

log_info "6. Limpeza (quando terminar):"
echo "   k3d cluster delete traefik"
echo ""
