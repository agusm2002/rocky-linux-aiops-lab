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
- [ ] **Fase 2**: Infrastructure as Code — OpenTofu
- [ ] **Fase 3**: Secrets Management — HashiCorp Vault
- [ ] **Fase 4**: K3s + Stack de Observabilidad
- [ ] **Fase 5**: Workflows de Automatización con n8n
- [ ] **Fase 6**: CI/CD y Documentación Final

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
- Acceso SSH con clave configurada
- Ansible instalado en la máquina de control

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
├── k3s/manifests/
│   ├── vault/
│   ├── prometheus/
│   ├── alertmanager/
│   ├── loki/
│   ├── alloy/
│   ├── grafana/
│   └── n8n/
└── docs/
```

## Lecciones Aprendidas

*(Se completará al final del proyecto — comparación con el proyecto 1)*