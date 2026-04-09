#!/usr/bin/env bash
#
# SPDX-FileCopyrightText: 2025 Buoyant Inc.
# SPDX-License-Identifier: Apache-2.0
#
# Copyright 2022-2025 Buoyant Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License"); you may
# not use this file except in compliance with the License.  You may obtain
# a copy of the License at
#
#     http:#www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

clear

# Create a K3d cluster to run the Traefik demo.
CLUSTER=${CLUSTER:-traefik}
# echo "CLUSTER is $CLUSTER"

# Ditch any old cluster...
k3d cluster delete $CLUSTER &>/dev/null

# Pre-carregar imagem do podinfo (evita ImagePullBackOff)
echo "Pre-carregando imagem do podinfo..."
docker pull stefanprodan/podinfo:6.3.8 2>/dev/null || echo "⚠️  Aviso: falha ao fazer pull do podinfo (rede pode estar indisponível)"

#@SHOW

# Expose ports 80 and 443 to the local host, so that our ingress can work.
# Also, don't install traefik, since we don't need it.
k3d cluster create $CLUSTER \
  --port 80:80@loadbalancer \
  --port 443:443@loadbalancer \
  --port 8000:8000@loadbalancer \
  --k3s-arg "--disable=traefik@server:0"

echo ""
echo "Importando imagem do podinfo para o cluster..."
k3d image import stefanprodan/podinfo:6.7.0 -c $CLUSTER 2>/dev/null || echo "⚠️  Aviso: falha ao importar podinfo"

echo ""
echo "Aguardando cluster ficar pronto..."
sleep 3

# Instalar MetalLB para LoadBalancer IPs reais
echo ""
echo "Instalando MetalLB..."
helm repo add metallb https://metallb.github.io/metallb
helm repo update
helm install metallb metallb/metallb \
  -n metallb-system \
  --create-namespace \
  --wait \
  --timeout=300s

sleep 5

echo "Configurando pool de IPs para MetalLB..."
kubectl apply -f - <<EOF
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: default
  namespace: metallb-system
spec:
  addresses:
  - 172.20.255.1-172.20.255.250
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: default
  namespace: metallb-system
spec:
  ipAddressPools:
  - default
EOF

echo ""
echo "✓ MetalLB instalado com sucesso!"
echo "✓ IPs disponíveis: 172.20.255.1 até 172.20.255.250"
echo ""

# if [ -f images.tar ]; then k3d image import -c ${CLUSTER} images.tar; fi
# #@wait
