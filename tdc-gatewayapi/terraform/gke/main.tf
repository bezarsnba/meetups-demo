provider "google" {
  project = var.project_id
}

# Cluster GKE Standard — não Autopilot: o Linkerd precisa de init container com
# NET_ADMIN/NET_RAW, o que gera atrito no Autopilot.
#
# A Gateway API nativa do GKE fica desabilitada de propósito: quem instala e
# gerencia os CRDs é o chart do Envoy Gateway (via Helm), evitando conflito de
# versões com o controller gke-l7 — que não usamos, pois o gateway precisa ser
# um pod dentro do cluster para entrar no mesh do Linkerd.

resource "google_container_cluster" "demo" {
  name     = var.cluster_name
  location = var.zone

  remove_default_node_pool = true
  initial_node_count       = 1
  deletion_protection      = false

  release_channel {
    channel = "REGULAR"
  }

  gateway_api_config {
    channel = "CHANNEL_DISABLED"
  }
}

resource "google_container_node_pool" "default" {
  name       = "default-pool"
  cluster    = google_container_cluster.demo.name
  location   = var.zone
  node_count = var.node_count

  node_config {
    machine_type = var.machine_type
    disk_size_gb = 50

    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform",
    ]
  }
}

# IPs estáticas regionais para os dois LoadBalancer da demo (ingress-nginx e
# Envoy Gateway) — sem isso, cada `helm upgrade`/recriação de Service pode
# trocar o IP, invalidando QR code e URL sslip.io já preparados com
# antecedência. Precisam estar na mesma região do cluster (o LB do GKE para
# Service type=LoadBalancer é regional, não zonal nem global).
resource "google_compute_address" "ingress" {
  name         = "${var.cluster_name}-ingress"
  region       = local.region
  address_type = "EXTERNAL"
}

resource "google_compute_address" "gateway" {
  name         = "${var.cluster_name}-gateway"
  region       = local.region
  address_type = "EXTERNAL"
}

locals {
  # "southamerica-east1-a" -> "southamerica-east1"
  region = join("-", slice(split("-", var.zone), 0, 2))
}
