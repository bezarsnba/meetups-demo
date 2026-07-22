output "cluster_name" {
  value = google_container_cluster.demo.name
}

output "get_credentials" {
  description = "Comando para configurar o kubectl"
  value       = "gcloud container clusters get-credentials ${google_container_cluster.demo.name} --zone ${var.zone} --project ${var.project_id}"
}

output "ingress_ip" {
  description = "IP estático reservado para o ingress-nginx (Ato 1)"
  value       = google_compute_address.ingress.address
}

output "gateway_ip" {
  description = "IP estático reservado para o Envoy Gateway (Ato 2/3)"
  value       = google_compute_address.gateway.address
}

output "services_ipv4_cidr" {
  description = "CIDR de Services do cluster — o GKE usa uma faixa fora do default do Linkerd (clusterNetworks), precisa ser somada nele"
  value       = google_container_cluster.demo.services_ipv4_cidr
}
