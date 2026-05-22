# ──────────────────────────────────────────────
# Infrastructure as Code — OpenTofu + Kubernetes
# Rocky Linux AIOps Lab
# ──────────────────────────────────────────────
#
# OpenTofu es IaC declarativa: define el estado deseado y reconcilia
# el estado real contra él. Si un recurso se elimina manualmente,
# `tofu apply` lo recrea. Esto es la diferencia fundamental con
# Ansible (configuration management procedural).
# ──────────────────────────────────────────────

terraform {
  required_version = ">= 1.7"

  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.30"
    }
  }
}

# ──────────────────────────────────────────────
# Provider — Kubernetes (apunta al kubeconfig de k3s)
# ──────────────────────────────────────────────

provider "kubernetes" {
  config_path = var.kubeconfig_path
}

# ──────────────────────────────────────────────
# Namespace — aiops
# ──────────────────────────────────────────────

resource "kubernetes_namespace" "aiops" {
  metadata {
    name = var.namespace

    labels = {
      "app.kubernetes.io/part-of" = "aiops-lab"
      "managed-by"                = "opentofu"
    }
  }
}

# ──────────────────────────────────────────────
# ConfigMap — Prometheus base config
# ──────────────────────────────────────────────

resource "kubernetes_config_map" "prometheus" {
  metadata {
    name      = "prometheus-config"
    namespace = kubernetes_namespace.aiops.metadata[0].name
    labels = {
      "app.kubernetes.io/name"    = "prometheus"
      "app.kubernetes.io/part-of" = "aiops-lab"
    }
  }

  data = {
    "prometheus.yml" = <<-YAML
      global:
        scrape_interval: 15s
        evaluation_interval: 15s

      scrape_configs:
        - job_name: 'prometheus'
          static_configs:
            - targets: ['localhost:9090']

        - job_name: 'node-exporter'
          static_configs:
            - targets: ['node-exporter:9100']

        - job_name: 'k3s-metrics'
          static_configs:
            - targets: ['k3s-server:9100']

      rule_files:
        - 'alert_rules.yml'

      alerting:
        alertmanagers:
          - static_configs:
              - targets: ['alertmanager:9093']
    YAML

    "alert_rules.yml" = <<-YAML
      groups:
        - name: aiops-alerts
          rules:
            - alert: HighCPU
              expr: 100 - (avg by(instance)(rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100) > 80
              for: 5m
              labels:
                severity: warning
              annotations:
                summary: "High CPU usage on {{ $labels.instance }}"

            - alert: DiskSpaceLow
              expr: node_filesystem_avail_bytes{mountpoint=\"/\"} / node_filesystem_size_bytes{mountpoint=\"/\"} * 100 < 20
              for: 5m
              labels:
                severity: warning
              annotations:
                summary: "Low disk space on {{ $labels.instance }}"

            - alert: ServiceDown
              expr: up == 0
              for: 2m
              labels:
                severity: critical
              annotations:
                summary: "Service {{ $labels.job }} is down"
    YAML
  }
}

# ──────────────────────────────────────────────
# ConfigMap — Grafana datasources (provisioning)
# ──────────────────────────────────────────────

resource "kubernetes_config_map" "grafana" {
  metadata {
    name      = "grafana-datasources"
    namespace = kubernetes_namespace.aiops.metadata[0].name
    labels = {
      "app.kubernetes.io/name"    = "grafana"
      "app.kubernetes.io/part-of" = "aiops-lab"
    }
  }

  data = {
    "datasources.yml" = <<-YAML
      apiVersion: 1
      datasources:
        - name: Prometheus
          type: prometheus
          access: proxy
          url: http://prometheus:9090
          isDefault: true
          editable: true

        - name: Loki
          type: loki
          access: proxy
          url: http://loki:3100
          editable: true
    YAML
  }
}
