# Workflows de n8n — Fase 5

## Archivos

| Archivo | Descripción | Nodos |
|---|---|---|
| `test-opencode-connection.json` | Paso 0: valida que n8n pueda llegar a OpenCode Go API con la API key inyectada por Vault. | 2 |
| `incident-response.json` | Workflow 1: recibe webhooks de Alertmanager, analiza la alerta con LLM y notifica Discord. | 4 |
| `log-analysis.json` | Workflow 2: cada hora consulta Loki, resume logs de error con LLM y envía reporte a Discord. | 5 |
| `health-check.json` | Workflow 3: cada 5 minutos consulta la API de K8s, filtra pods fallidos, analiza con LLM y notifica Discord (o loguea "all healthy" a Loki). | 8 |

## Importar en n8n

1. Port-forward a n8n:
   ```bash
   kubectl port-forward -n aiops svc/n8n 5678:5678
   ```

2. Abrí [http://localhost:5678](http://localhost:5678) e ingresá.

3. Andá a **Workflows** → **Add Workflow** → **Import from File**.

4. Seleccioná cada `.json` de esta carpeta.

5. Activá el workflow con el toggle **Active**.

## Credenciales requeridas

Los workflows leen automáticamente de las variables de entorno inyectadas por Vault Agent:

- `N8N_OPENCODE_API_KEY` — Bearer token para `https://opencode.ai/zen/go/v1/chat/completions`
- `N8N_DISCORD_WEBHOOK_URL` — URL del webhook de Discord

Si la API key no está configurada en Vault (`secret/data/n8n/credentials`), los workflows de LLM fallarán.

## Endpoints expuestos

- **Incident Response**: `POST http://n8n.aiops.svc.cluster.local:5678/webhook/alertmanager`
  - Alertmanager ya está configurado para enviar alertas a este endpoint (`alertmanager/configmap.yml`).
