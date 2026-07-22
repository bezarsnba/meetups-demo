variable "project_id" {
  description = "Projeto GCP onde o cluster será criado"
  type        = string
}

variable "zone" {
  description = "Zona do cluster (São Paulo por padrão — menor latência para a plateia)"
  type        = string
  default     = "southamerica-east1-a"
}

variable "cluster_name" {
  description = "Nome do cluster GKE"
  type        = string
  default     = "tdc-gatewayapi"
}

variable "machine_type" {
  description = "Tipo de máquina dos nós"
  type        = string
  default     = "e2-standard-2"
}

variable "node_count" {
  description = "Quantidade de nós do pool"
  type        = number
  default     = 3
}
