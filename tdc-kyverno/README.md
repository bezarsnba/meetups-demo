# Governança no Kubernetes sem Dor — Kyverno

TDC Florianópolis · 24/07/2026 · Trilha Arquitetura Cloud · 30min

Garantir que tudo que roda no cluster segue as políticas da organização é
impossível de forma manual. Esta demo mostra o Kyverno resolvendo isso em
três frentes — validar, mutar e gerar recursos — e depois as mesmas regras
funcionando sem nenhuma configuração extra dentro de um pipeline GitOps real
(ArgoCD).

## Estrutura

- `local/k3d.yaml` — cluster k3d dedicado desta talk (`tdc-kyverno`)
- `policies/` — as 3 `ClusterPolicy` do Kyverno usadas na demo
  - `01-disallow-latest-tag.yaml` (validate) — bloqueia deployments fora do padrão
  - `02-mutate-mandatory-labels.yaml` (mutate) — força labels obrigatórias
  - `03-generate-default-networkpolicy.yaml` (generate) — gera NetworkPolicy por namespace
- `gitops/argocd/application.yaml` — Application do ArgoCD usada na Parte 4
- `gitops/apps/demo-app/` — manifests sincronizados pelo ArgoCD (fonte da verdade da demo)
- `tests/` — `kyverno-test.yaml` + fixtures: testa `disallow-latest-tag` sem cluster (shift-left, rodável em CI)
- `scripts/install-components.sh` — sobe cluster + Kyverno + ArgoCD + Policy Reporter + políticas
- `demo.md` — roteiro para [demosh](https://github.com/BuoyantIO/demosh)

## Acesso ao ArgoCD UI

```bash
kubectl --context=k3d-tdc-kyverno -n argocd port-forward svc/argocd-server 8080:443
# https://localhost:8080 (aceite o certificado self-signed)
# usuário: admin
# senha:
kubectl --context=k3d-tdc-kyverno -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d
```

## Policy Reporter (dashboard de compliance)

```bash
kubectl -n policy-reporter port-forward service/policy-reporter-ui 8082:8080
# http://localhost:8082/
```

## Testando as políticas sem cluster

```bash
kyverno test tests/
```

## Rodando

```bash
./scripts/install-components.sh
demosh demo.md
```

## Referências

- https://kyverno.io
- CNCF Policy Working Group
