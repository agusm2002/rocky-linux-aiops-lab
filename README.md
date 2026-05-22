# rocky-linux-aiops-lab

> Self-hosted ITOps automation platform on Rocky Linux: n8n orchestrating incident response workflows triggered by Prometheus alerts and Loki log patterns, with LLM analysis via OpenCode Go API — deployed on k3s, provisioned with Ansible, secrets managed with HashiCorp Vault, and infrastructure defined as code with OpenTofu.

## Stack Tecnológico

| Capa | Tecnología | Notas |
|---|---|---|
| OS | Rocky Linux 9 | RHEL-based, ecosistema RPM |
| Seguridad base | SELinux enforcing + firewalld | Diferencia clave vs Ubuntu/UFW |
| Secrets management | HashiCorp Vault | Reemplaza Kubernetes Secrets en base64 |
| Provisioning | Ansible | Roles de hardening RHEL |
| IaC | OpenTofu | Fork open source de Terraform, provider Kubernetes |
| Orquestación | k3s | Kubernetes certificado, single-node, ARM64 |
| Métricas | Prometheus + Alertmanager | Alertmanager cierra el loop con n8n |
| Logs | Loki + Grafana Alloy | Alloy es el sucesor oficial de Promtail |
| Dashboards | Grafana | Métricas, logs y ejecuciones de n8n |
| Automatización | n8n | Orquestador de workflows de ITOps |
| LLM | OpenCode Go API | Endpoint compatible OpenAI, modelos DeepSeek/Kimi/Qwen |
| CI/CD | GitHub Actions | Lint y validación de YAML, Ansible y OpenTofu |

## Estado del Proyecto

- [x] **Fase 1**: Base del Sistema — Rocky Linux + Hardening RHEL
- [x] **Fase 2**: Infrastructure as Code — OpenTofu
- [ ] **Fase 3**: Secrets Management — HashiCorp Vault
- [x] **Fase 4**: K3s + Stack de Observabilidad
- [ ] **Fase 5**: Workflows de Automatización con n8n
- [ ] **Fase 6**: CI/CD y Documentación Final

> **Nota:** La Fase 3 (Vault) se ejecuta después de la Fase 4 porque Vault se despliega dentro de k3s. El README marca la Fase 4 como completada antes que la 3 por esta dependencia lógica.

## Diferencias clave: Rocky Linux / RHEL vs Ubuntu

| Concepto | Ubuntu | Rocky Linux / RHEL |
|---|---|---|
| Firewall | UFW | firewalld (zones + services) |
| SELinux | Desactivado por defecto | Enforcing por defecto |
| Paquetes | apt / dpkg | dnf / rpm |
| SSH service | ssh | sshd |
| Gestión de servicios | systemd | systemd (igual) |
| Repositorios | PPA | EPEL, CRB |

## Inicio Rápido

### Prerrequisitos

- Rocky Linux 9 (ARM64) corriendo en UTM o similar
- Acceso SSH con clave configurado (puerto 2222)
- Ansible instalado en la máquina de control (Mac)
- k3s corriendo en la VM (ver sección Fase 4)

### Ejecutar el playbook de hardening

```bash
cd ansible
ansible-playbook playbooks/site.yml
```

### Idempotencia

Correr el playbook dos veces y confirmar que el segundo run no reporta cambios:

```bash
ansible-playbook playbooks/site.yml
ansible-playbook playbooks/site.yml  # Segunda corrida — no debería haber cambios
```

## Estructura del Repositorio

```
rocky-linux-aiops-lab/
├── README.md
├── .github/workflows/
├── ansible/
│   ├── inventory/hosts.yml
│   ├── roles/
│   │   ├── system-base/
│   │   ├── firewalld/
│   │   ├── selinux/
│   │   ├── ssh-hardening/
│   │   └── vault-agent/
│   └── playbooks/site.yml
├── tofu/
│   ├── main.tf
│   ├── variables.tf
│   └── outputs.tf
├── k3s/manifests/
│   ├── namespace.yml
│   ├── prometheus/
│   │   ├── serviceaccount.yml    # RBAC para kubernetes_sd_configs
│   │   ├── configmap.yml         # Prometheus config + alert rules
│   │   ├── deployment.yml + PVC
│   │   ├── service.yml
│   │   └── node-exporter.yml     # DaemonSet para métricas del host
│   ├── alertmanager/
│   │   ├── configmap.yml
│   │   ├── deployment.yml
│   │   └── service.yml
│   ├── loki/
│   │   ├── configmap.yml
│   │   ├── deployment.yml
│   │   ├── service.yml
│   │   └── pvc.yml
│   ├── alloy/
│   │   ├── configmap.yml
│   │   ├── daemonset.yml
│   │   ├── service.yml
│   │   ├── serviceaccount.yml
│   │   └── rbac.yml
│   ├── grafana/
│   │   ├── configmap.yml              # Datasources + dashboard provider
│   │   ├── dashboard-configmap.yml   # Cluster Overview dashboard JSON
│   │   ├── deployment.yml + PVC
│   │   ├── service.yml
│   │   ├── ingress.yml
│   │   └── secret.yml
│   ├── n8n/
│   │   ├── configmap.yml
│   │   ├── deployment.yml + PVC
│   │   ├── service.yml
│   │   ├── ingress.yml
│   │   └── secret.yml
│   └── vault/
└── docs/
```

## IaC Declarativa vs Configuration Management (Fase 2)

| Concepto | Ansible (CM) | OpenTofu (IaC) |
|---|---|---|
| Paradigma | Procedural — pasos en orden | Declarativo — estado deseado |
| Estado | No rastrea estado internamente | Mantiene state file (terraform.tfstate) |
| Idempotencia | Manual — el playbook la implementa | Automática — `tofu apply` solo aplica diff |
| Drift detection | No — corre todo otra vez | Sí — `tofu plan` muestra drift |
| Recreación | No — si un cambio falla, queda a medias | Sí — si un recurso se elimina manualmente, `tofu apply` lo recrea |
| Cuándo usar | Configurar paquetes, servicios, usuarios del SO | Definir recursos cloud/K8s (namespaces, deployments, PVC) |

Son complementarios: OpenTofu crea los recursos, Ansible los configura.

## Fase 2 — OpenTofu: flujo de trabajo

```bash
cd tofu
tofu init       # Inicializa providers
tofu plan       # Muestra qué va a crear/drift
tofu apply      # Aplica los cambios
tofu show       # Inspecciona el state
tofu destroy    # Elimina todo (ciclo completo)
```

Recursos definidos:
- `kubernetes_namespace.aiops` — namespace `aiops` con labels
- `kubernetes_config_map.prometheus` — configuración de Prometheus + alert rules
- `kubernetes_config_map.grafana` — datasources de Grafana (Prometheus + Loki)

## Conceptos de Kubernetes (Fase 4)

| Concepto | Descripción |
|---|---|
| Pod | Unidad mínima, uno o más contenedores |
| Deployment | Define cuántas réplicas correr y cómo actualizarlas |
| DaemonSet | Un pod por cada nodo del cluster — usado por Alloy y Node Exporter |
| Service | Expone un pod internamente en el cluster (ClusterIP) |
| Ingress | Expone servicios fuera del cluster — Traefik en k3s por defecto |
| ConfigMap | Configuración no sensible montada como archivos |
| Secret | Configuración sensible (passwords) codificada en base64 |
| PVC | Almacenamiento persistente — k3s usa local-path por defecto |
| Namespace | Separación lógica — todos los servicios en `aiops` |

## Fase 4 — k3s + Stack de Observabilidad

### Instalación de k3s

```bash
# En la VM Rocky Linux:
curl -sfL https://get.k3s.io | sh -

# Verificar:
sudo kubectl get nodes
sudo kubectl get pods -A

# Copiar kubeconfig para acceso desde la Mac:
scp -P 2222 rocky-aiops:/etc/rancher/k3s/k3s.yaml ~/.kube/config
# Editar server: cambiar 127.0.0.1 por la IP de la VM
```

### Desplegar el stack

```bash
# Desde la Mac, con kubeconfig apuntando a la VM:
kubectl apply -f k3s/manifests/namespace.yml

# Observabilidad (en orden de dependencia):
kubectl apply -f k3s/manifests/prometheus/
kubectl apply -f k3s/manifests/alertmanager/
kubectl apply -f k3s/manifests/loki/
kubectl apply -f k3s/manifests/alloy/
kubectl apply -f k3s/manifests/grafana/

# Automatización:
kubectl apply -f k3s/manifests/n8n/
```

### Arquitectura del stack

```
                    ┌──────────────────────────────────────────────┐
                    │              Mac (navegador)                 │
                    │   grafana.local ──► Grafana Ingress :80    │
                    │   n8n.local ──────► n8n Ingress :80        │
                    └──────────┬───────────────────────────────────┘
                               │
                    ┌──────────┴───────────────────────────────────┐
                    │           k3s cluster (aiops ns)            │
                    │                                             │
                    │  ┌─────────────┐    ┌──────────────────┐  │
                    │  │ Prometheus   │───►│  Alertmanager    │  │
                    │  │ :9090       │    │  :9093            │  │
                    │  └──┬──────────┘    └───────┬──────────┘  │
                    │     │ scrape              │ webhook        │
                    │  ┌──┴──────────┐    ┌──────┴──────────┐  │
                    │  │Node Exporter │    │     n8n          │  │
                    │  │ :9100       │    │  :5678 /metrics  │  │
                    │  └─────────────┘    └─────────────────┘  │
                    │                                             │
                    │  ┌─────────────┐    ┌──────────────────┐  │
                    │  │  Grafana    │    │  Alloy (DaemonSet)│  │
                    │  │ :3000       │◄───│  recolecta logs  │  │
                    │  └──────┬──────┘    └───────┬──────────┘  │
                    │         │ datasource        │ push logs    │
                    │  ┌──────┴──────┐    ┌───────┴──────────┐  │
                    │  │ Prometheus  │    │    Loki           │  │
                    │  │ :9090       │    │  :3100            │  │
                    │  └─────────────┘    └──────────────────┘  │
                    └─────────────────────────────────────────────┘
```

### Servicios desplegados

| Servicio | Imagen | Puerto | Función |
|---|---|---|---|
| Prometheus | prom/prometheus:v2.51.0 | 9090 | Scrape y almacenamiento de métricas |
| Node Exporter | prom/node-exporter:v1.7.0 | 9100 | Métricas del host (CPU, memoria, disco) |
| Alertmanager | prom/alertmanager:v0.27.0 | 9093 | Routing de alertas a n8n |
| Loki | grafana/loki:2.9.6 | 3100 | Almacenamiento y query de logs |
| Alloy | grafana/alloy:v1.1.0 | 12345 | Recolección de logs de pods |
| Grafana | grafana/grafana:10.4.1 | 3000 | Dashboards y visualización |
| n8n | n8nio/n8n:1.36.4 | 5678 | Orquestación de workflows |

## Lecciones Aprendidas

*(Se completará al final del proyecto — comparación con el proyecto 1)*