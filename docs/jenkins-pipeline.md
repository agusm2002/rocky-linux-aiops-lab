# Pipeline de CI/CD — Jenkins

## Configuración

### 1. Crear el job en Jenkins

```bash
kubectl port-forward -n aiops svc/jenkins 8080:8080
```

Abrir [http://localhost:8080](http://localhost:8080) → login con `admin` / password del secret.

1. **New Item** → nombre: `aiops-lab-pipeline` → tipo: **Pipeline**
2. En **Pipeline** → Definition: `Pipeline script from SCM`
3. SCM: `Git`
4. Repository URL: `https://github.com/agusm2002/rocky-linux-aiops-lab`
5. Branch: `feat/fase-7.5-mejoras-practicas-stack`
6. Script Path: `Jenkinsfile`
7. Save

### 2. Configurar el webhook de Discord

En el job → **Configure** → **General**:

- Marcar **This project is parameterized**
- Agregar **String Parameter**:
  - Name: `DISCORD_WEBHOOK_URL`
  - Default Value: la URL completa del webhook de Discord
  - Description: Webhook URL for Discord notifications

### 3. Stages del pipeline

| Stage | Qué hace | Herramienta |
|---|---|---|
| Lint YAML | Valida sintaxis de todos los .yml en `k3s/manifests/` | `yamllint` |
| Lint Ansible | Valida playbooks y roles en `ansible/` | `ansible-lint` |
| Validate OpenTofu | `tofu validate` en `tofu/local/` | OpenTofu 1.9 |
| Validate K8s Manifests | `kubectl --dry-run=client apply` en todos los manifests | kubectl |

### 4. Notificaciones

El pipeline notifica en cada ejecución:

| Resultado | Discord | n8n |
|---|---|---|
| ✅ Success | `✅ Pipeline OK — commit abc1234` | POST a `/webhook/jenkins-success` |
| ❌ Failure | `❌ Pipeline FAILED — commit abc1234` | POST a `/webhook/jenkins-failure` |

El `post { failure }` demuestra que el pipeline no solo corre en verde — también
notifica cuando algo falla. Eso es CI/CD real.

### 5. Ejecutar manualmente

En el job → **Build with Parameters** → completar el `DISCORD_WEBHOOK_URL` → **Build**.

## Métricas en Grafana

Jenkins expone métricas en `/prometheus` que se visualizan en el dashboard
**AIOps Automation Health** de Grafana:

- `jenkins_runs_total_total` — Total de ejecuciones
- `jenkins_runs_failure_total` — Ejecuciones fallidas
- `jenkins_runs_success_total` — Ejecuciones exitosas
- `jenkins_queue_size_value` — Jobs en cola
- `default_jenkins_builds_last_build_duration_milliseconds` — Duración del último build
