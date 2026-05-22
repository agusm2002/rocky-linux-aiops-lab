# ──────────────────────────────────────────────
# Variables — Rocky Linux AIOps Lab
# ──────────────────────────────────────────────

variable "kubeconfig_path" {
  description = "Ruta al kubeconfig de k3s (en la VM Rocky Linux)"
  type        = string
  default     = "~/.kube/config"
}

variable "namespace" {
  description = "Namespace principal para el stack de AIOps"
  type        = string
  default     = "aiops"
}

variable "prometheus_retention" {
  description = "Tiempo de retención de métricas en Prometheus"
  type        = string
  default     = "15d"
}

variable "grafana_admin_password" {
  description = "Password del usuario admin de Grafana (reemplazar por Vault en Fase 3)"
  type        = string
  default     = "admin"
  sensitive   = true
}
