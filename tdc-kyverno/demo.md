# Demo — Governança no Kubernetes sem Dor (Kyverno)

Roteiro para [demosh](https://github.com/BuoyantIO/demosh). Pressupõe que
`scripts/install-components.sh` já rodou e o cluster `tdc-kyverno` está de pé.

Tempo total de talk: 30min. Este roteiro cobre só a demo ao vivo (~20-22min),
deixando o resto para introdução e fechamento no deck.

<!-- @SHOW -->

## Parte 1 — Validate: bloqueando o que foge do padrão

A política em si — regra `validate`, `Enforce`, aplicada em background pra pegar
até recurso que já existia antes dela.

```bash
bat --paging=never policies/01-disallow-latest-tag.yaml
```

<!-- @wait -->

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

A política — regra `mutate`, injeta `team`/`environment` só se ainda não existirem.

```bash
bat --paging=never policies/02-mutate-mandatory-labels.yaml
```

<!-- @wait -->

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

A política — regra `generate`, dispara em todo `Namespace` novo (exceto os de
sistema) e mantém sincronizado (`synchronize: true`).

```bash
bat --paging=never policies/03-generate-default-networkpolicy.yaml
```

<!-- @wait -->

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

<!-- @wait_clear -->

### E se isso fosse pego antes do PR ser mergeado?

O cluster acabou de recusar — mas esperar o ArgoCD sincronizar pra descobrir
o erro é tarde. `kyverno test` roda a mesma política contra o mesmo manifest
sem cluster nenhum, local ou no CI.

```bash
kyverno test tests/
```

<!-- @wait -->

`podinfo-latest` falha, `podinfo-pinned` passa — o mesmo `disallow-latest-tag`
usado no cluster, testado como código antes do PR ser aberto. Shift-left pra
pegar o erro cedo, admission webhook pra garantir que nada passa despercebido
se alguém pular o teste.

<!-- @wait_clear -->

Corrigindo a fonte da verdade — no Git, não no cluster.

```bash
sed -i 's/podinfo:latest/podinfo:6.6.2/' gitops/apps/demo-app/deployment.yaml
git add gitops/apps/demo-app/deployment.yaml
git commit -m "fix: pin podinfo image tag"
git push
```

<!-- @wait -->

O ArgoCD faz polling do Git a cada 3min por padrão — rápido demais pra esperar
ao vivo. Forçando um refresh pra ele detectar o commit na hora.

```bash
kubectl -n argocd annotate application demo-app argocd.argoproj.io/refresh=hard --overwrite
sleep 5
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

## Parte 5 — Report: o raio-x contínuo do cluster

Tudo que vimos até aqui foi pontual — um `kubectl` de cada vez. O Kyverno
também mantém um resultado de compliance por recurso, o tempo todo, em
background.

```bash
kubectl get policyreport -n demo-app
```

<!-- @wait -->

Isso é o que o **Policy Reporter** transforma num dashboard: abrindo a UI.

```bash
kubectl -n policy-reporter port-forward service/policy-reporter-ui 8082:8080 >/tmp/policy-reporter-pf.log 2>&1 &
sleep 1
```

<!-- @wait -->

Abrir `http://localhost:8082/` — visão consolidada de pass/fail por política,
por namespace, sem precisar rodar `kubectl` pra cada recurso. É a peça que
fecha o argumento de governança: não é só bloquear no momento do deploy, é
ter visibilidade contínua do estado de conformidade do cluster.

```bash
kill %1 2>/dev/null || true
```

<!-- @wait_clear -->

Validate bloqueou, Mutate corrigiu, Generate protegeu, `kyverno test` pegou
antes do PR, ArgoCD sincronizou, Policy Reporter documentou tudo — governança
como código, do PR ao cluster em produção.
