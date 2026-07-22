# Gateway API com Linkerd — demo ao vivo

<!--
Script para `demosh` (https://github.com/BuoyantIO/demosh).
Pressupõe que o cluster GKE já está provisionado: ingress-nginx, Envoy
Gateway (com CRDs da Gateway API), Linkerd (control-plane + viz), o app
(podinfo v1/v2) e o EnvoyProxy `envoy-static-ip` já instalados via Helm/
kubectl — ver docs/gke.md. O patch no Ato 2 amarra o Gateway ao IP estático
reservado no Terraform (necessário só no GKE — Gateway.spec.addresses,
o campo "oficial", é ignorado lá: envoyproxy/gateway#4335).

Este arquivo só aplica os manifests dos 3 atos. Roda com:
  demosh demo.md

SPDX-FileCopyrightText: 2026 Bezaleel Silva
SPDX-License-Identifier: Apache-2.0
-->

<!-- @SKIP -->

## Checagem silenciosa antes de subir no palco

Confere rapidinho que a infra da talk está de pé antes de começar a mostrar
qualquer coisa pra plateia. Se algo aqui falhar, não segue pro `@SHOW`.

```bash
#@immed
kubectl get pods -n ingress-nginx --no-headers | grep -q Running &&
kubectl get pods -n envoy-gateway-system --no-headers | grep -qv Running || true
kubectl get pods -n linkerd --no-headers
kubectl get pods -n linkerd-viz --no-headers
kubectl get pods -n apps --no-headers
```

<!-- @SHOW -->

# Gateway API com Linkerd

## Roteamento Inteligente no Kubernetes Além do Ingress

Bora começar. Ato 1: o "antes" — Ingress clássico.

<!-- @wait -->

## Ato 1 — Ingress: o antes

Dois `Ingress` disputando a mesma rota, canary só via annotation
vendor-specific do nginx.

```bash
bat ato1-ingress/ingress-main.yaml
```

```bash
bat ato1-ingress/ingress-canary.yaml
```

Repare em `nginx.ingress.kubernetes.io/canary-weight` — um typo aqui é
silenciosamente ignorado pelo Kubernetes.

```bash
kubectl apply -f ato1-ingress/
```

```bash
./scripts/get-url.sh ingress
```

<!-- @wait_clear -->

## Ato 2 — Gateway API

3 recursos, 3 donos: `GatewayClass` (provedor) → `Gateway` em `infra`
(plataforma) → `HTTPRoute` em `apps` (dev).

`GatewayClass` — papel do provedor: qual controller implementa a API. Trocar
de implementação (Envoy, Istio, Traefik...) é trocar essa referência —
Gateway e HTTPRoute não mudam.

```bash
bat ato2-gateway/gatewayclass.yaml
```

`Gateway` — papel da plataforma: listeners, TLS, e **quem pode conectar**
(`allowedRoutes` restrito por label, no namespace `infra`).

```bash
bat ato2-gateway/gateway.yaml
```

`HTTPRoute` — papel do dev: as rotas, no namespace do time (`apps`). Canary
e pesos vivem aqui, na spec — o dev tem autonomia sem pedir PR no repo da
plataforma.

```bash
bat ato2-gateway/httproute-100-0.yaml
```

```bash
kubectl apply -f ato2-gateway/namespace.yaml
kubectl apply -f ato2-gateway/gatewayclass.yaml
kubectl apply -f ato2-gateway/gateway.yaml
kubectl apply -f ato2-gateway/httproute-100-0.yaml
```

```bash
#@immed
kubectl patch gateway demo-gateway -n infra --type=merge -p \
  '{"spec":{"infrastructure":{"parametersRef":{"group":"gateway.envoyproxy.io","kind":"EnvoyProxy","name":"envoy-static-ip"}}}}'
```

```bash
./scripts/get-url.sh gateway
```

<!-- @wait -->

Canary ao vivo — pesos na spec, validados pela API, sem annotation.

```bash
bat ato2-gateway/httproute-90-10.yaml
```

```bash
#@waitafter
kubectl apply -f ato2-gateway/httproute-90-10.yaml
```

```bash
bat ato2-gateway/httproute-50-50.yaml
```

```bash
#@waitafter
kubectl apply -f ato2-gateway/httproute-50-50.yaml
```

Plateia vê as cores alternando no celular. Agora desliga o "antes":

```bash
kubectl delete -f ato1-ingress/
```

<!-- @wait_clear -->

## Ato 3 — Linkerd

Mesheia o app e o próprio Gateway (Envoy Gateway é um pod). O script anota
os namespaces `apps` e `envoy-gateway-system` com `linkerd.io/inject=enabled`
e reinicia os deployments — é isso que injeta o sidecar `linkerd-proxy` em
cada pod. Meshar o Gateway (não só o app) é o ponto-chave: o mTLS passa a
cobrir o caminho inteiro, gateway → app, não só serviço → serviço.

```bash
bat ato3-linkerd/mesh.sh
```

```bash
./ato3-linkerd/mesh.sh
```

<!-- @wait -->

Prova o mTLS ponta a ponta:

```bash
linkerd viz edges deployment -n apps
```

```bash
linkerd viz stat deploy -n apps
```

<!-- @wait -->

Rate limit por identidade mTLS — protege o canary (v2), não por IP:

```bash
bat ato3-linkerd/ratelimit-canary.yaml
```

```bash
kubectl apply -f ato3-linkerd/ratelimit-canary.yaml
```

```bash
kubectl run curl-debug -n apps --image=curlimages/curl --restart=Never \
  --annotations="linkerd.io/inject=enabled" --command -- sleep 3600
kubectl wait --for=condition=Ready pod/curl-debug -n apps --timeout=60s
```

Burst no canary — os primeiros ~5 passam, o resto vem `429`:

```bash
kubectl exec -n apps curl-debug -c curl-debug -- sh -c \
  'for i in $(seq 1 30); do curl -s -o /dev/null -w "%{http_code}\n" http://podinfo-v2.apps.svc.cluster.local:9898/; done' \
  | sort | uniq -c
```

O v1 (estável) segue livre:

```bash
kubectl exec -n apps curl-debug -c curl-debug -- sh -c \
  'for i in $(seq 1 30); do curl -s -o /dev/null -w "%{http_code}\n" http://podinfo-v1.apps.svc.cluster.local:9898/; done' \
  | sort | uniq -c
```

```bash
#@immed
kubectl delete pod -n apps curl-debug
```

<!-- @wait_clear -->

## Clímax — QR code

```bash
./scripts/get-url.sh gateway
```

Gera o QR code dessa URL no telão. Plateia acessa pelo celular, RPS sobe ao
vivo:

```bash
linkerd viz dashboard
```

<!-- @wait -->

"Uma API só, da borda ao mesh." Obrigado!
