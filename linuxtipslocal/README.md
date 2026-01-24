<!--
SPDX-FileCopyrightText: 2024 Buoyant Inc.
SPDX-License-Identifier: Apache-2.0

SMA-Description: Getting Started with Linkerd
-->



#  Meetup LinuxTips

Esta é a documentação — e código executável! — para o laboratório de Service Mesh com Linkerd apresentado no meetup da LinuxTips. A forma mais fácil de usar este arquivo é executá-lo com o [demosh].

Comentários em Markdown podem ser ignorados ao ler depois. Ao executar com o [demosh], tudo após a linha horizontal abaixo (logo antes da diretiva comentada `@SHOW`) será exibido.

[demosh]: https://github.com/BuoyantIO/demosh

Este laboratório requer que você tenha um cluster Kubernetes em funcionamento. O README assume que você está usando um cluster com suporte a serviços LoadBalancer, de modo que você possa obter o IP externo e acessá-lo. (No Mac, provavelmente será necessário usar o [OrbStack](https://orbstack.dev) para clusters locais.)

<!-- @import demosh/check-requirements.sh -->
<!-- @start_livecast -->
---
<!-- @SHOW -->


# Linkerd service mesh

Bem-vindo ao Linkerd 101! Neste workshop, vamos mostrar:

- como instalar a CLI do Linkerd
- como usar a CLI para instalar o Linkerd em um cluster Kubernetes
- como configurar uma aplicação de demonstração propositalmente "quebrada"
- como usar o Linkerd para observar a aplicação
- como usar o Linkerd para melhorar o comportamento da aplicação

Para começar, vamos garantir que nosso cluster está vazio.

```bash
kubectl get ns
kubectl get all
```


Tudo certo até aqui! Agora, vamos instalar a CLI do Linkerd.

<!-- @wait_clear -->



# Instalando a CLI do Linkerd

Para este laboratório, usaremos a versão open source do Linkerd.

Você pode instalar a CLI do Linkerd com o comando abaixo:

```bash
curl -sL https://run.linkerd.io/install | sh
export PATH=$PATH:$HOME/.linkerd2/bin
```

Verifique se a instalação foi bem-sucedida:

```bash
linkerd version
```

Pronto! Agora, vamos garantir que o cluster está apto a rodar o Linkerd:

```bash
linkerd check --pre
```

Você deve ver todos os itens em verde. Se não, corrija os erros antes de prosseguir.

<!-- @wait_clear -->


# Instalando os CRDs do Linkerd

Agora, precisamos instalar os CRDs do Linkerd. Isso é feito uma única vez por cluster e permite que o Linkerd estenda o Kubernetes com recursos personalizados. Use o comando abaixo:

```
linkerd install --crds  | kubectl apply -f -
```


Você verá esse padrão várias vezes: a CLI do `linkerd` nunca modifica o cluster diretamente. Ela gera YAMLs do Kubernetes e imprime no stdout, permitindo que você inspecione, modifique, faça commit para GitOps ou apenas envie direto para o `kubectl apply`, como estamos fazendo aqui.

<!-- @wait -->


Vamos instalar os CRDs:

```bash
#kubectl apply -f \
#    https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.2.1/standard-install.yaml
#
linkerd install --crds --set installGatewayAPI=true | kubectl apply -f -
```


Agora estamos prontos para instalar o control plane! Mas antes, vamos listar algumas simplificações feitas neste laboratório...

<!-- @wait_clear -->


## SIMPLIFICAÇÕES

**1. A CLI do `linkerd` está gerenciando os CRDs do Gateway API.**

Isso é aceitável para o laboratório porque não vamos usar o Linkerd junto com outros projetos de Gateway API. Em ambientes reais, o ideal seria gerenciar esses CRDs separadamente.

<!-- @wait_clear -->


# Instalando o Control Plane do Linkerd

Vamos instalar o control plane! É mais um comando simples:

```
linkerd install | kubectl apply -f -
```

Isso instalará o control plane no namespace `linkerd`, mas não vai esperar todos os pods subirem. Sempre que quiser, use `linkerd check` (sem o `--pre`) para garantir que tudo está funcionando.

No laboratório, podemos rodar os dois comandos em sequência:

```bash
linkerd install | kubectl apply -f -
linkerd check
```

Agora, o Linkerd deve estar rodando no namespace `linkerd` do seu cluster! Se quiser, veja o que está rodando:

```bash
kubectl get ns
kubectl get pods -n linkerd
```

Hora de adicionar mais uma simplificação...

<!-- @wait_clear -->


## SIMPLIFICAÇÕES

1. A CLI do `linkerd` está gerenciando os CRDs do Gateway API.

**2. A CLI do `linkerd` também está gerenciando os certificados.**

O Linkerd usa mTLS para comunicação segura — e isso exige certificados. Neste laboratório, deixamos a CLI do `linkerd` gerar os certificados automaticamente. Não é recomendado para produção, mas facilita muito para fins didáticos!

<!-- @wait_clear -->


# Instalando o Linkerd Viz

Vamos instalar o Linkerd Viz, que fornece um dashboard para observar o que está acontecendo no cluster. Assim como no control plane, usamos a CLI do `linkerd` para gerar os manifestos e aplicamos, depois rodamos o `linkerd check` para garantir que tudo está funcionando:

```bash
linkerd viz install | kubectl apply -f -
linkerd check
```

Agora, você verá o namespace `linkerd-viz` criado com alguns recursos:

```bash
kubectl get ns
kubectl get pods -n linkerd-viz
```

E podemos abrir o dashboard em um navegador:

```bash
linkerd viz dashboard
```

E temos mais uma simplificação para destacar aqui!

<!-- @wait_clear -->


## SIMPLIFICAÇÕES

1. A CLI do `linkerd` está gerenciando os CRDs do Gateway API.
2. A CLI do `linkerd` está gerenciando os certificados.

**3. Deixamos o Linkerd Viz instalar o Prometheus para nós.**

O Linkerd Viz é uma camada de visualização baseada no Prometheus, então precisa de um Prometheus rodando. Se você não especificar o contrário, o `linkerd viz install` instalará um Prometheus — mas ele armazena os dados apenas em memória, então você perderá tudo ao reiniciar (o que é comum). Em produção, use seu próprio Prometheus.

<!-- @wait_clear -->


# Instalando o Faces Demo

Agora que o Linkerd está rodando, vamos instalar uma aplicação de demonstração para brincar. Usaremos o famoso Faces demo, uma aplicação propositalmente "quebrada" para mostrar como as coisas podem ficar complexas mesmo com poucos microserviços: veja em <https://github.com/BuoyantIO/faces-demo>.

Comece criando um namespace para o Faces:

```bash
kubectl create ns faces
```

Depois, anote o namespace para que o Linkerd injete o sidecar automaticamente em todos os pods criados nele:

```bash
kubectl annotate ns faces linkerd.io/inject=enabled
```

Agora, use o Helm para instalar o Faces! A única configuração extra é definir `gui.serviceType` como `LoadBalancer` (para simular um ingress controller) e habilitar os workloads `smiley2` e `color2`.

```bash
helm install -n faces faces \
     oci://ghcr.io/buoyantio/faces-chart \
     --version 2.0.0-rc.2 \
     --set gui.serviceType=LoadBalancer \
     --set smiley2.enabled=true \
     --set color2.enabled=true
```

Por fim, aguarde o Faces ficar disponível:

```bash
kubectl rollout status -n faces deploy
```

Com o Faces rodando, conecte-se ao serviço `faces-gui` no namespace `faces` para acessar a interface. O método depende do seu cluster:

- Se estiver usando um cluster local criado com o script `create-cluster.sh`, o serviço estará disponível em `http://localhost/`.
- Em clusters de nuvem, use o IP externo do serviço `faces-gui`.
- Se nada disso funcionar, use `kubectl port-forward` para acessar.

<!-- @browser_then_terminal -->

Mais uma simplificação aqui também.

<!-- @wait_clear -->


## SIMPLIFICAÇÕES

1. A CLI do `linkerd` está gerenciando os CRDs do Gateway API.
2. A CLI do `linkerd` está gerenciando os certificados.
3. Deixamos o Linkerd Viz instalar o Prometheus.

**4. Não estamos usando um ingress controller para o Faces.**

Isso é só para economizar tempo no laboratório. No mundo real, nunca exponha sua aplicação diretamente na internet: use um ingress controller seguro!

<!-- @wait_clear -->


# Observando o Faces com o Linkerd

O Faces claramente não está funcionando bem. Vamos ver o que o Linkerd pode nos mostrar imediatamente. Comece acessando o Linkerd Viz novamente:

O Linkerd Viz traz uma enorme quantidade de informações, desde o status do mTLS até as "golden metrics"! (Tudo isso também está disponível via linha de comando, mas não vamos mostrar neste laboratório.)

Essas informações mostram que o Faces está em péssimo estado: os workloads `face`, `smiley` e `color` estão falhando cerca de 20% das vezes, o que explica o que vemos na interface. Vamos ver como melhorar isso.
 
<!-- @wait_clear -->
<!-- @show_5 -->


# Retries (Repetições)
**O que são retries?**

Retries (repetições) são tentativas automáticas de reenviar uma requisição quando ocorre uma falha temporária entre serviços. No Linkerd, você pode configurar retries facilmente usando anotações nos serviços do Kubernetes. Isso aumenta a resiliência da aplicação, pois pequenas falhas momentâneas deixam de impactar o usuário final.

Por exemplo, se um serviço falhar ao responder, o Linkerd pode tentar novamente antes de retornar um erro. Isso reduz a quantidade de erros visíveis na interface e melhora a experiência do usuário, especialmente em sistemas distribuídos onde falhas intermitentes são comuns.

No entanto, é importante usar retries com moderação, pois muitas tentativas podem aumentar a carga sobre os serviços e gerar outros problemas. O ideal é encontrar um equilíbrio entre resiliência e desempenho.


Uma coisa óbvia que podemos fazer aqui é adicionar tentativas automáticas (retries). Vamos começar pelos rostos roxos tristes: eles aparecem quando o "ingress" (na verdade o workload `faces-gui`) recebe uma falha do workload `face`. Podemos resolver isso adicionando retries ao serviço `face`. Os rostos roxos devem praticamente sumir da interface assim que rodarmos este comando:



```bash
kubectl annotate -n faces svc face retry.linkerd.io/http=5xx
```

"Praticamente" porque estamos permitindo apenas uma repetição. Se o workload `face` falhar duas vezes seguidas, ainda veremos um rosto roxo. Podemos reduzir isso permitindo mais tentativas:

```bash
kubectl annotate -n faces svc face retry.linkerd.io/limit=3
```

Agora não deveríamos mais ver rostos roxos! Por outro lado, se voltarmos ao Linkerd Viz, veremos que a carga no `face` aumentou bastante: retries melhoram a experiência do usuário, mas não protegem o serviço!

```bash
linkerd viz dashboard
```

<!-- @clear -->


# Retries (continuação)

Agora, vamos resolver os rostos "xingando": eles aparecem quando o workload `face` recebe uma falha do workload `smiley`. Podemos resolver isso anotando o serviço `smiley`:

```bash
kubectl annotate -n faces svc smiley \
  retry.linkerd.io/http=5xx \
  retry.linkerd.io/limit=3
```

Por fim, os fundos cinzas aparecem quando o `face` recebe uma falha do `color`. Como é uma requisição gRPC, a anotação é um pouco diferente:

```bash
kubectl annotate -n faces svc color \
  retry.linkerd.io/grpc=internal \
  retry.linkerd.io/limit=3
```

Isso deve eliminar os fundos cinzas!

<!-- @wait -->


...mas isso não funcionou. Por quê?

<!-- @wait_clear -->

# Retries

O motivo é que o Linkerd enxerga o tráfego gRPC como HTTP, a menos que apliquemos um GRPCRoute para informar que aquele tráfego é realmente gRPC. Vamos fazer isso para `color` e `color2`:

```bash
bat color-routes.yaml
kubectl apply -f color-routes.yaml
```

Depois disso, os fundos cinzas somem da interface.

É interessante voltar ao dashboard do Viz e ver como os retries aparecem...

```bash
linkerd viz dashboard
```

<!-- @clear -->
<!-- @show_terminal -->


# Retries e Estatísticas

A resposta curta é que, na verdade, os retries não aparecem de forma explícita no dashboard Viz — eles só parecem tráfego extra. Porém, temos uma ferramenta de linha de comando que pode ajudar:

```bash
linkerd viz stat-outbound -n faces deploy/face
```

Esse comando é ótimo para obter mais detalhes do que está acontecendo. Se a saída ficar difícil de ler, podemos usar um script Python para remover as colunas `LATENCY_P95` e `LATENCY_P99`:

```bash
linkerd viz stat-outbound -n faces deploy/face | python3 filter-stats.py
```

<!-- @wait_clear -->
<!-- @show_5 -->


# Roteamento Dinâmico

Podemos fazer muito mais em termos de confiabilidade, mas para não estender demais, vamos mostrar só mais uma coisa: roteamento dinâmico de requisições. Primeiro, vamos instalar um HTTPRoute que redireciona todas as requisições de `smiley` para `smiley2`. Assim, todos os quadrados terão carinhas de coração no lugar dos sorrisos normais.

```bash
bat all-heart-eyes.yaml
kubectl apply -f all-heart-eyes.yaml
```

Se olharmos novamente no Linkerd Viz, veremos o tráfego para `smiley` cair e o tráfego para `smiley2` subir (isso não é imediato, depende do intervalo de amostragem).

```bash
linkerd viz dashboard
```

<!-- @clear -->
<!-- @show_5 -->


# Roteamento Dinâmico (continuação)

Também podemos fazer roteamento mais granular, não apenas redirecionar todo o tráfego. O workload `face` usa dois caminhos diferentes ao falar com o `smiley`:

- `/center` para os quatro quadrados centrais
- `/edge` para os quadrados das bordas

Vamos modificar o HTTPRoute para redirecionar apenas os quadrados das bordas para o `smiley2` (carinhas de coração):

```bash
bat edge-heart-eyes.yaml
kubectl apply -f edge-heart-eyes.yaml
```

<!-- @wait_clear -->


# Roteamento Dinâmico (final)

Podemos fazer o mesmo para o workload `color`: ele usa os métodos gRPC `Center` e `Edge` para diferenciar os quadrados centrais e das bordas. Vamos fazer os quadrados centrais ficarem com fundo verde (usando o `color2`) e deixar as bordas como estão:

```bash
bat edge-green.yaml
kubectl apply -f edge-green.yaml
```

<!-- @wait_clear -->
<!-- @show_terminal -->


# Encerrando

Esse foi um tour rápido pelos conceitos básicos do Linkerd. Há muito mais que poderíamos explorar:

- O roteamento dinâmico de requisições combina perfeitamente com progressive delivery e GitOps, dando controle total em qualquer ponto do fluxo.

<!-- @wait -->

- Além de retries, o Linkerd suporta timeouts, circuit breaking, rate limiting e controle de saída (egress).

<!-- @wait -->

- O Linkerd tem recursos multicluster poderosos e pode até estender o mesh para workloads fora do Kubernetes.

<!-- @wait -->

- O Buoyant Enterprise for Linkerd inclui o Buoyant Lifecycle Operator, que automatiza a instalação e gestão do Linkerd no cluster, além de recursos extras para tráfego entre zonas.

<!-- @wait -->

- O BEL também inclui ferramentas para geração de políticas.

Para saber mais sobre tudo isso, acesse https://buoyant.io/sma!

Por fim, feedbacks são sempre bem-vindos! Você pode me encontrar em flynn@buoyant.io ou como @flynn no Slack do Linkerd (https://slack.linkerd.io).

<!-- @wait -->
<!-- @show_slides -->
