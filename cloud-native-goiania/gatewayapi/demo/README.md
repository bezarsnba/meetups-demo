<!-- @SHOW -->

# Gateway API: Ingress vs HTTPRoute

Este demo mostra a **coexistência** entre o Ingress tradicional (nginx) e o
novo padrão Gateway API (HTTPRoute via Traefik), ilustrando o caminho de
migração sem downtime.

- **Ingress** (nginx): método legado com annotations vendor-specific
- **HTTPRoute** (Traefik): padrão CNCF moderno, sem annotations

<!-- @wait_clear -->

# Passo 1: Instalar Gateway API CRDs v1.4.0

O Gateway API é um padrão CNCF que define recursos como `Gateway`,
`HTTPRoute`, `GRPCRoute` e outros. Os CRDs precisam ser instalados primeiro.

```bash
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.4.0/standard-install.yaml
```

```bash
kubectl wait --for=condition=Established \
  crd/gatewayclasses.gateway.networking.k8s.io \
  --timeout=60s
```

```bash
kubectl get crds | grep gateway.networking
```

<!-- @wait_clear -->

# Passo 2: Instalar Traefik v3 (controller Gateway API)

O Traefik v3 suporta **três providers simultaneamente**:
- `kubernetesGateway`: lê `HTTPRoute`
- `kubernetesIngress`: lê `Ingress` com `ingressClass: traefik`
- `kubernetesIngressNginx`: lê `Ingress` com `ingressClass: nginx`

```bash
helmfile -f helmfile/traefik/helmfile.yaml sync
```

```bash
kubectl wait --for=condition=Ready pod \
  -l app.kubernetes.io/name=traefik \
  -n traefik \
  --timeout=300s
```

```bash
kubectl get pods -n traefik
kubectl get svc -n traefik
```

<!-- @wait_clear -->

# GatewayClass criado pelo Traefik

Quando o Traefik sobe, ele registra automaticamente um `GatewayClass`.
Qualquer `Gateway` que referencie `traefik` será controlado por ele.

```bash
kubectl get gatewayclasses
```

```bash
kubectl describe gatewayclass traefik
```

<!-- @wait_clear -->

# Passo 3: Instalar Ingress-Nginx (controller legado)

O nginx-ingress cria a `IngressClass` chamada `nginx`. O Traefik monitora
esta classe via provider `kubernetesIngressNginx`, permitindo descobrir
recursos Ingress mesmo sem ser o controller principal.

```bash
helmfile -f helmfile/nginx-ingress/helmfile.yaml sync
```

```bash
kubectl wait --for=condition=Ready pod \
  -l app.kubernetes.io/name=ingress-nginx \
  -n ingress-nginx \
  --timeout=300s
```

```bash
kubectl get pods -n ingress-nginx
kubectl get svc -n ingress-nginx
kubectl get ingressclass
```

<!-- @wait_clear -->

# Passo 4: Deploy da aplicação de exemplo (Podinfo)

Uma única aplicação será exposta pelos dois métodos ao mesmo tempo,
demonstrando a coexistência.

```bash
kubectl apply -f manifests/50-simple-app.yaml
```

```bash
kubectl wait --for=condition=Available deployment/podinfo \
  -n demo-app \
  --timeout=120s
```

```bash
kubectl get pods -n demo-app
kubectl get svc -n demo-app
```

<!-- @wait_clear -->

# O Problema: Ingress Tradicional

O Ingress usa annotations vendor-specific para configurar comportamentos.
Isso cria acoplamento com o controller escolhido — mudar de controller
pode quebrar as configurações.

```bash
bat manifests/51-ingress-legacy.yaml
```

```bash
kubectl apply -f manifests/51-ingress-legacy.yaml
```

```bash
kubectl get ingress -n demo-app -o wide
```

<!-- @wait_clear -->

# Ingress respondendo via nginx

Vamos confirmar que o Ingress está funcionando via nginx-ingress.

```bash
NGINX_IP=$(kubectl get svc ingress-nginx-controller -n ingress-nginx -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo "Nginx IP: ${NGINX_IP}"
```

```bash
curl -si http://${NGINX_IP} -H 'Host: app.localhost' | head -20
```

<!-- @wait_clear -->

# Migração: Mudando o IngressClass para Traefik

O Traefik já monitora Ingress com `ingressClassName: nginx` via provider
`kubernetesIngressNginx`. Basta trocar a classe — **sem reescrever nada**.

```bash
kubectl patch ingress podinfo-ingress -n demo-app \
  --type='json' \
  -p='[{"op":"replace","path":"/spec/ingressClassName","value":"traefik"}]'
```

```bash
kubectl get ingress -n demo-app -o wide
```

<!-- @wait_clear -->

# Nada mudou — página continua respondendo

O mesmo Ingress agora é servido pelo Traefik. Zero downtime.

```bash
TRAEFIK_IP=$(kubectl get svc traefik -n traefik -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo "Traefik IP: ${TRAEFIK_IP}"
```

```bash
curl -si http://${TRAEFIK_IP} -H 'Host: app.localhost' | head -20
```

<!-- @wait_clear -->

# Removendo o Ingress

Agora que validamos que o Traefik funciona, podemos remover o Ingress
e migrar completamente para o Gateway API.

```bash
kubectl delete -f manifests/51-ingress-legacy.yaml
```

```bash
kubectl get ingress -n demo-app
```

<!-- @wait_clear -->

# Gateway API: o próximo passo

Agora aplicamos o modelo moderno — sem annotations, com separação clara
entre **infra team** (Gateway) e **app team** (HTTPRoute).

```bash
bat manifests/01-gateway.yaml
```

```bash
kubectl apply -f manifests/01-gateway.yaml
```

```bash
kubectl get gateway -n demo-app
kubectl get httproute -n demo-app
```

<!-- @wait_clear -->

# Validando: Gateway API respondendo

```bash
curl -si http://${TRAEFIK_IP} -H 'Host: app.localhost' | head -20
```

<!-- @wait_clear -->

# Resumo da Migração

| Etapa | Recurso | Controller | Status |
|-------|---------|------------|--------|
| 1 | `Ingress` (nginx) | nginx-ingress | ✅ funcionando |
| 2 | `Ingress` (traefik) | Traefik | ✅ zero downtime |
| 3 | `HTTPRoute` + `Gateway` | Traefik | ✅ moderno |

<!-- @wait_clear -->

# Resumo

**Gateway API** é o futuro do roteamento no Kubernetes:

- ✅ Padrão CNCF oficial (stable desde 2023)
- ✅ Sem annotations vendor-specific
- ✅ Separação de responsabilidades (infra vs app team)
- ✅ Features nativas: headers, query params, method matching
- ✅ Migração gradual sem downtime

```bash
kubectl get gatewayclasses
kubectl get gateway -n demo-app
kubectl get httproute -n demo-app
kubectl get ingress -n demo-app
```

<!-- @wait -->

# Limpeza

```bash
k3d cluster delete traefik
```

<!-- @HIDE -->
