# SLOs del AIOps Lab

Este documento define los Service Level Objectives (SLOs) del stack AIOps.
Cada SLO tiene un SLI medible, un objetivo numérico y un error budget que
determina cuánto downtime es aceptable por mes.

Todos los SLIs se miden con Prometheus y se visualizan en el dashboard
**Cluster Overview** de Grafana.

---

## Grafana — Interfaz de Observabilidad

| Campo | Valor |
|---|---|
| **SLI** | % de tiempo que el endpoint de Grafana responde al scrape de Prometheus |
| **SLO** | 99.9% de disponibilidad mensual |
| **Error Budget** | 43.8 minutos de downtime por mes (30 días) |
| **Query PromQL** | `avg_over_time(up{job="grafana"}[30d]) * 100` |
| **Alerta asociada** | `GrafanaSLOBreach` — dispara si la disponibilidad en 1h baja del 99.9% |

**¿Por qué 99.9%?** Grafana es la UI principal del stack. Si no está
disponible, los dashboards de monitoreo no se pueden consultar y la
capacidad de respuesta del equipo se degrada. 43.8 minutos al mes de
downtime es razonable para un entorno de laboratorio.

**Panel en Grafana:** Stat `SLO — Grafana (24h)` + Gauge `Error Budget — Grafana`
que muestra los minutos de downtime ya consumidos en el mes.

---

## n8n — Orquestador de Automatización

| Campo | Valor |
|---|---|
| **SLI** | % de tiempo que n8n responde al scrape de Prometheus |
| **SLO** | 99.9% de disponibilidad mensual |
| **Error Budget** | 43.8 minutos de downtime por mes |
| **Query PromQL** | `avg_over_time(up{job="n8n"}[30d]) * 100` |
| **Alerta asociada** | `N8nDown` — dispara si n8n deja de responder por 1 minuto |

**¿Por qué 99.9%?** n8n es el orquestador central: recibe webhooks de
Alertmanager, ejecuta health checks, y envía notificaciones a Discord.
Si n8n no está disponible, el pipeline de auto-remediación se rompe.
Es el single point of failure más crítico del stack.

**Panel en Grafana:** Stat `SLO — n8n (24h)`.

---

## Prometheus — Motor de Métricas y Alertas

| Campo | Valor |
|---|---|
| **SLI** | % de targets que responden al scrape (promedio de todos los `up`) |
| **SLO** | 99.9% de disponibilidad mensual |
| **Error Budget** | 43.8 minutos de downtime por mes |
| **Query PromQL** | `avg(up) * 100` |
| **Alerta asociada** | `ServiceDown` — dispara si cualquier target deja de responder 2 minutos |

**¿Por qué 99.9%?** Si Prometheus no puede scrapear los targets, perdemos
visibilidad de todo el cluster. Las alertas no se generan, los dashboards
quedan vacíos, y los SLOs de los demás servicios no se pueden medir.

---

## Jenkins — Pipeline de CI/CD

| Campo | Valor |
|---|---|
| **SLI** | % de builds exitosos sobre el total de ejecuciones |
| **SLO** | 95% de builds exitosos |
| **Error Budget** | 5% de builds fallidos permitidos |
| **Query PromQL** | `jenkins_runs_success_total / jenkins_runs_total_total * 100` |

**¿Por qué 95%?** En un lab, los builds pueden fallar por cambios experimentales.
Un 5% de fallos es aceptable; más de eso indica un problema sistemático
en el pipeline o en el código.

**Panel en Grafana:** Stat `Jenkins — Success Rate` en el dashboard
**AIOps Automation Health**.

---

## Cómo leer el Error Budget

El **Error Budget** es el tiempo de downtime que "nos podemos permitir"
sin violar el SLO. Se calcula como:

```
Error Budget (minutos) = (1 - SLO) × minutos_en_el_período
```

Para un SLO de 99.9% en 30 días:

```
(1 - 0.999) × 30 × 24 × 60 = 43.8 minutos
```

**Regla de SRE:** Si el error budget se consume por completo, se debe
pausar todo deploy o cambio hasta que la confiabilidad se recupere.

El panel **Error Budget — Grafana** en el dashboard muestra un gauge:
- 🟢 Verde: < 20 min consumidos (presupuesto sano)
- 🟡 Amarillo: 20–40 min consumidos (atención)
- 🔴 Rojo: > 40 min consumidos (SLO en riesgo, pausar deploys)

---

## Alertas que protegen los SLOs

| Alerta | SLO protegido | Dispara cuando |
|---|---|---|
| `GrafanaSLOBreach` | Grafana 99.9% | Disponibilidad < 99.9% en la última hora |
| `N8nDown` | n8n 99.9% | n8n no responde por 1 minuto |
| `ServiceDown` | Prometheus 99.9% | Cualquier target no responde por 2 minutos |
| `HighMemoryUsage` | Indirecto | Memoria > 85% — puede causar OOMKill |
| `DiskSpaceLow` | Indirecto | Disco > 80% — puede causar fallos de escritura |

---

## Verificación

Para validar que los SLOs se están midiendo correctamente:

```bash
# Disponibilidad de Grafana en los últimos 30 días
kubectl exec -n aiops deploy/prometheus -- wget -qO- \
  'http://localhost:9090/api/v1/query?query=avg_over_time(up{job="grafana"}[30d])*100'

# Error budget consumido este mes (minutos)
kubectl exec -n aiops deploy/prometheus -- wget -qO- \
  'http://localhost:9090/api/v1/query?query=(1-avg_over_time(up{job="grafana"}[30d]))*30*24*60'
```
