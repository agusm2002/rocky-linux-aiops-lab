# OCI Free Tier — Límites Reales

> Fuente: https://www.oracle.com/cloud/free/
> Fecha de consulta: 2026-05-27
> Región: Brazil East (sa-saopaulo-1)

---

## Compute

| Recurso | Límite Always Free | Qué usa el plan Fase 9 |
|---|---|---|
| **AMD Compute** | 2 VMs (1/8 OCPU + 1 GB c/u) | 0 — no se usan |
| **ARM Ampere A1** | 3,000 OCPU horas/mes + 18,000 GB horas/mes | 4 OCPU × 24h × 30d = 2,880 hrs ✅ (96% usado) |
| | | 24 GB × 24h × 30d = 17,280 GB hrs ✅ (96% usado) |

> ⚠️ El límite no es "4 OCPUs + 24 GB", es por **horas de consumo mensual**. Si las VMs corren 24/7 los 30 días del mes, estás al 96% del límite — justo pero dentro.

---

## Storage

| Recurso | Límite Always Free | Qué usa el plan Fase 9 |
|---|---|---|
| **Block Volume** | 200 GB total + 5 backups | 150 GB (50 bastion + 100 k3s) ✅ (75%) |
| **Object Storage — Standard** | 20 GB (compartido con Archive e Infrequent) | Loki con retention 7d: estimado < 2 GB ✅ |
| **Object Storage — API Requests** | 50,000 req/mes | ⚠️ Loki genera PUTs por cada chunk de log. Si corre 24/7, podría exceder. Ver mitigación abajo. |
| **Archive Storage** | Incluido en los 20 GB | 0 — no se usa |

---

## Networking

| Recurso | Límite Always Free | Qué usa el plan Fase 9 |
|---|---|---|
| **VCN** | 2 VCNs | 1 VCN ✅ |
| **Load Balancer** | 1 instancia, 10 Mbps | 0 — no se usa (tráfico directo a IP pública) |
| **Flexible NLB** | 1 instancia | 0 — no se usa |
| **Site-to-Site VPN** | 50 conexiones | 0 — no se usa |
| **VCN Flow Logs** | 10 GB/mes | No configurado |
| **Outbound Data Transfer** | 10 TB/mes | < 1 GB para un lab ✅ |
| **Service Connector Hub** | 2 conectores | 0 — no se usa |

---

## Security

| Recurso | Límite Always Free | Qué usa el plan Fase 9 |
|---|---|---|
| **Vault** | 20 key versions + 150 secrets | 1 key + 3 secrets ✅ |
| **Bastions** | 5 OCI Bastions | 0 — usamos nuestra propia VM como bastion |
| **Certificates** | 5 Private CA + 150 TLS certs | 0 — no se usa |

---

## Observability

| Recurso | Límite Always Free | Qué usa el plan Fase 9 |
|---|---|---|
| **Monitoring** | 500M ingestion + 1B retrieval datapoints | Prometheus y Grafana locales (no usan OCI Monitoring) ✅ |
| **Logging** | 10 GB/mes | No se usa (Loki va a Object Storage) ✅ |
| **Notifications** | 1M HTTPS + 1,000 email/mes | No se usa (n8n manda a Discord) ✅ |
| **Email Delivery** | 100 emails/día | No se usa ✅ |
| **APM** | 1,000 tracing events/hora | No se usa ✅ |

---

## Databases

| Recurso | Límite Always Free | Qué usa el plan Fase 9 |
|---|---|---|
| **Autonomous DB** | 2 databases | 0 — no se usa |
| **HeatWave** | 1 instancia + 50 GB | 0 — no se usa |
| **NoSQL** | 3 tablas, 25 GB c/u | 0 — no se usa |

---

## Others

| Recurso | Límite Always Free | Qué usa el plan Fase 9 |
|---|---|---|
| **Console Dashboards** | 100 dashboards | No se usa |
| **APEX** | 744 horas/instancia | No se usa |

---

## ⚠️ Análisis de riesgos reales

### Riesgo 1: Object Storage API Requests (50,000/mes)

Loki escribe chunks a Object Storage. En un escenario de lab con baja carga (pocos pods, pocos logs), el consumo debería ser bajo. Pero si corrés la VM 24/7 con retention de 31 días y muchos servicios logueando, podrías acercarte o pasar los 50K requests.

**Mitigación:** 
- El configmap `loki/configmap-oci.yml` ya tiene `retention_period: 168h` (7 días)
- Si querés ser conservador, **no actives Loki en OCI** durante la demo — mantenelo con filesystem local en la VM y documentá que OCI Object Storage está configurado y listo pero no activo 24/7
- Alternativa: usar Loki con filesystem en OCI (como en local) y Object Storage solo queda documentado como "ready for production"

### Riesgo 2: ARM OCPU hours (2,880 de 3,000)

Si el mes tiene 31 días: 4 × 24 × 31 = 2,976 horas. Sigue dentro (99.2%). Pero si Oracle mide distinto o hay redondeo, podrías estar al borde.

**Mitigación:** Pará las VMs cuando no las uses. Con 8h/día de uso real, consumís solo ~960 OCPU horas/mes.

### Riesgo 3: Capacidad Ampere A1

Esto no es costo, es disponibilidad. Oracle puede rechazar `tofu apply` si no hay capacidad ARM en ese momento.

**Mitigación:** Intentar en horarios de baja demanda (madrugada). Si falla, esperar 1-2 horas y reintentar.

### Riesgo 4: Block Volume — no hay riesgo (150 de 200 GB)

### Riesgo 5: Vault — no hay riesgo (3 secrets de 150)
