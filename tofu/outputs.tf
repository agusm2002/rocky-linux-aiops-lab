# ──────────────────────────────────────────────
# Outputs — Rocky Linux AIOps Lab
# ──────────────────────────────────────────────

output "namespace_name" {
  description = "Nombre del namespace creado"
  value       = kubernetes_namespace.aiops.metadata[0].name
}

output "prometheus_configmap_name" {
  description = "Nombre del ConfigMap de Prometheus"
  value       = kubernetes_config_map.prometheus.metadata[0].name
}

output "grafana_configmap_name" {
  description = "Nombre del ConfigMap de Grafana"
  value       = kubernetes_config_map.grafana.metadata[0].name
}
