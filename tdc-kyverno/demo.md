# Demo — Governança no Kubernetes sem Dor (Kyverno)

Roteiro para [demosh](https://github.com/BuoyantIO/demosh). Pressupõe que
`scripts/install-components.sh` já rodou e o cluster `tdc-kyverno` está de pé.

Tempo total de talk: 30min. Este roteiro cobre só a demo ao vivo (~20-22min),
deixando o resto para introdução e fechamento no deck.

<!-- @SHOW -->

## Parte 1 — Validate: bloqueando o que foge do padrão

Tentando subir um Pod com tag `:latest` — prática que o time de plataforma não permite.

```bash
kubectl run bad-pod --image=nginx:latest --restart=Never
```

<!-- @wait -->

O admission webhook do Kyverno rejeita na hora, com a mensagem da política —
sem CI, sem linter externo, sem esperar um pipeline rodar.

```bash
kubectl get clusterpolicy disallow-latest-tag
```

<!-- @wait_clear -->

## Parte 2 — Mutate: labels obrigatórias sem travar o deploy

Um Deployment chega sem as labels que o time de plataforma exige — mas dessa vez
a política não bloqueia, ela **corrige**.

```bash
kubectl create deployment sample --image=nginx:1.27
```

<!-- @wait -->

```bash
kubectl get deployment sample --show-labels
```

<!-- @wait -->

`team` e `environment` foram preenchidos automaticamente com um valor default —
o Kyverno mutou o recurso antes dele ser persistido no etcd.

```bash
kubectl delete deployment sample
```

<!-- @wait_clear -->

## Parte 3 — Generate: NetworkPolicy sem ninguém lembrar de criar

Criando um namespace novo, do jeito que qualquer time criaria.

```bash
kubectl create namespace time-pagamentos
```

<!-- @wait -->

```bash
kubectl get networkpolicy -n time-pagamentos
```

<!-- @wait -->

Uma `NetworkPolicy` default-deny nasceu junto com o namespace — ninguém no time
precisou saber que ela existe pra estar protegido.

```bash
kubectl delete namespace time-pagamentos
```

<!-- @wait_clear -->

## Parte 4 — GitOps: as mesmas regras, agora via ArgoCD

A `Application` do ArgoCD já está registrada e aponta pro diretório
`gitops/apps/demo-app` deste repo, com auto-sync ligado. O manifest lá dentro
usa `stefanprodan/podinfo:latest` de propósito.

```bash
kubectl get application demo-app -n argocd
```

<!-- @wait -->

Sync automático, mas o Deployment nunca fica saudável — o Kyverno recusa a
`:latest` mesmo vindo do ArgoCD, sem nenhuma configuração extra no pipeline.

```bash
kubectl get application demo-app -n argocd -o jsonpath='{.status.sync.status} / {.status.health.status}{"\n"}'
kubectl describe deployment podinfo -n demo-app | grep -A5 Events
```

<!-- @wait -->

Corrigindo a fonte da verdade — no Git, não no cluster.

```bash
sed -i 's/podinfo:latest/podinfo:6.6.2/' gitops/apps/demo-app/deployment.yaml
git add gitops/apps/demo-app/deployment.yaml
git commit -m "fix: pin podinfo image tag"
git push
```

<!-- @wait -->

```bash
kubectl get application demo-app -n argocd -o jsonpath='{.status.sync.status} / {.status.health.status}{"\n"}'
kubectl get deployment podinfo -n demo-app --show-labels
kubectl get networkpolicy -n demo-app
```

<!-- @wait_clear -->

Sync, health, labels mutadas e NetworkPolicy gerada — as três políticas
aplicadas no mesmo recurso, sem nenhuma linha a mais no pipeline do ArgoCD.
