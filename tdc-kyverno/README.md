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
- `scripts/install-components.sh` — sobe cluster + Kyverno + ArgoCD + políticas
- `demo.md` — roteiro para [demosh](https://github.com/BuoyantIO/demosh)

## Rodando

```bash
./scripts/install-components.sh
demosh demo.md
```

## Referências

- https://kyverno.io
- CNCF Policy Working Group
