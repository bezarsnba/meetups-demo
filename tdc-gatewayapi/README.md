# TDC Florianópolis — Gateway API com Linkerd

Demo da palestra **"Gateway API com Linkerd: Roteamento Inteligente no Kubernetes Além do Ingress"**.

Progressão em 3 atos: Ingress clássico → Gateway API (Envoy Gateway) → Linkerd (mTLS + golden metrics),
terminando com a plateia acessando o cluster GKE pelo celular via QR code.

## Arquitetura

```
Internet (plateia via QR code)
  → IP público (GCP Network LB — Service type LoadBalancer)
    → Envoy Gateway (pod, injetado com Linkerd)      ← Gateway + listeners
      → HTTPRoute com traffic split 90/10
        → podinfo-v1 (azul) / podinfo-v2 (verde)     ← pods meshados, mTLS
```

O app é o [podinfo](https://github.com/stefanprodan/podinfo): a UI mostra versão e cor de fundo,
então o canary fica visível do celular (v1 azul, v2 verde).

## Estrutura do repo

```
demo.md          # script demosh — roda SÓ os yamls dos 3 atos (dia da talk)
terraform/gke/   # infraestrutura: cluster GKE (Terraform)
local/           # cluster local de ensaio: k3d.yaml
docs/            # guias de setup (só provisionamento): local.md (k3d) e gke.md (Terraform)
app/             # podinfo v1 e v2
ato1-ingress/    # o "antes": Ingress + canary via annotations
ato2-gateway/    # GatewayClass, Gateway (infra) e HTTPRoutes (apps)
ato3-linkerd/    # mesh.sh: injeta app + gateway no mesh
                 # ratelimit-canary.yaml: rate limit por identidade mTLS no podinfo-v2
scripts/         # get-url.sh: URL pública para o QR code
                 # install-components.sh: Helm/kubectl para o ambiente GKE (atalho de docs/gke.md)
```

## Setup

Escolha o ambiente:

- **[Ensaio local (k3d + MetalLB)](./docs/local.md)** — pra treinar o roteiro antes do dia.
- **[GKE (Terraform)](./docs/gke.md)** — infraestrutura real usada na palestra. **Só provisiona** (cluster + Helm) — não aplica nenhum manifest da demo.

Os dois terminam no mesmo estado: `ingress-nginx`, Envoy Gateway (com CRDs da
Gateway API), Linkerd e o app da demo instalados via Helm. A partir daí, existem
duas formas de rodar o roteiro dos 3 atos, com o **mesmo conteúdo**:

- **No dia da talk (GKE)**: `demosh demo.md` — script interativo que narra e
  pausa entre comandos ([instalar demosh](https://github.com/BuoyantIO/demosh#to-install-demosh)).
- **Manual/ensaio local**: seguir o [roteiro de palco](#roteiro-de-palco) abaixo, comando a comando.

## Roteiro de palco

### Ato 1 — Ingress: o "antes" (~3 min)

```bash
kubectl apply -f ato1-ingress/
./scripts/get-url.sh ingress
```

- Abrir `ato1-ingress/ingress-canary.yaml` no telão: canary só existe via **annotations**
  vendor-specific — e um typo em `canary-weight` é silenciosamente ignorado.
- Mostrar que main + canary são **dois Ingress disputando a mesma rota**, sem dono claro.

### Ato 2 — Gateway API (~6 min)

```bash
kubectl apply -f ato2-gateway/namespace.yaml
kubectl apply -f ato2-gateway/gatewayclass.yaml
kubectl apply -f ato2-gateway/gateway.yaml
kubectl apply -f ato2-gateway/httproute-100-0.yaml
./scripts/get-url.sh gateway        # URL pública → gerar QR code daqui
```

- Narrar os papéis: `GatewayClass` (provedor) → `Gateway` no namespace **infra**
  (plataforma, com `allowedRoutes` restrito por label) → `HTTPRoute` no namespace
  **apps** (dev).
- Canary ao vivo, sem annotation — pesos na spec, validados pela API:

```bash
kubectl apply -f ato2-gateway/httproute-90-10.yaml   # 10% verde
kubectl apply -f ato2-gateway/httproute-50-50.yaml   # plateia vê alternar no celular
```

- Desligar o Ingress ao vivo: `kubectl delete -f ato1-ingress/` — "o antes acabou".

### Ato 3 — Linkerd (~4 min)

```bash
./ato3-linkerd/mesh.sh              # injeta apps + envoy-gateway-system e reinicia
```

- Provar o mTLS de ponta a ponta (gateway → app):

```bash
linkerd viz edges deployment -n apps   # coluna SECURED = ✓
linkerd viz stat deploy -n apps        # golden metrics por deployment
linkerd viz dashboard
```

- **Protege o canary com rate limit por identidade mTLS** — diferencial do
  Linkerd: o limite é por identidade real do chamador (workload autenticado),
  não por IP (que quebra atrás de LB/NAT). Aqui protege especificamente o
  `podinfo-v2`, que ainda está em validação:

```bash
kubectl apply -f ato3-linkerd/ratelimit-canary.yaml   # Server + HTTPLocalRateLimitPolicy (5 rps) no v2

kubectl run curl-debug -n apps --image=curlimages/curl --restart=Never \
  --annotations="linkerd.io/inject=enabled" --command -- sleep 3600
kubectl wait --for=condition=Ready pod/curl-debug -n apps --timeout=60s

# burst no canary (v2) — os primeiros ~5 passam, o resto vem 429
kubectl exec -n apps curl-debug -c curl-debug -- sh -c \
  'for i in $(seq 1 30); do curl -s -o /dev/null -w "%{http_code}\n" http://podinfo-v2.apps.svc.cluster.local:9898/; done' \
  | sort | uniq -c

# o v1 (estável) não tem o Server/policy — sem limite, tudo 200
kubectl exec -n apps curl-debug -c curl-debug -- sh -c \
  'for i in $(seq 1 30); do curl -s -o /dev/null -w "%{http_code}\n" http://podinfo-v1.apps.svc.cluster.local:9898/; done' \
  | sort | uniq -c

kubectl delete pod -n apps curl-debug
```

- **Clímax**: QR code no telão → plateia acessa → RPS subindo ao vivo no dashboard,
  canary alternando cores, tudo com mTLS. "Mesma API da borda ao mesh."

## Resetar o ensaio (voltar ao estado pré-Ato 1)

```bash
kubectl delete -f ato1-ingress/ -f ato2-gateway/ --ignore-not-found
kubectl annotate namespace apps envoy-gateway-system linkerd.io/inject- --overwrite
kubectl rollout restart deployment -n apps
```

## Plano B (rede do evento falhou)

Os manifests são portáveis: suba um `kind` local, rode os mesmos passos de Helm
(o LoadBalancer fica pending — use `kubectl port-forward` ou
[cloud-provider-kind](https://github.com/kubernetes-sigs/cloud-provider-kind))
e apresente com `cloudflared tunnel` — ou com a gravação da demo.

## Backlog

- [ ] TLS público: ClusterIssuer Let's Encrypt (cert-manager com `enableGatewayAPI`) +
      listener HTTPS no Gateway usando `demo.<IP>.sslip.io`
- [ ] Ensaiar timing dos 3 atos com cronômetro
- [ ] Gravar a demo completa (plano B)
- [ ] Gerar QR code da URL final para o slide
