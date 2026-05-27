# Demo de Self-Healing con ArgoCD

Este documento describe cómo demostrar que ArgoCD está funcionando
como mecanismo de GitOps real, no solo como una herramienta instalada.

## Concepto

Con `syncPolicy.automated.selfHeal: true`, ArgoCD monitorea constantemente
el cluster. Si detecta que un recurso difiere de lo definido en Git,
lo restaura automáticamente. Esto convierte a Git en la **fuente de verdad**
del cluster.

## Escenario de demo

### 1. Verificar el estado inicial

```bash
# Todos los deployments deben estar healthy
kubectl get deployments -n aiops
```

### 2. Simular un error humano

Eliminar un deployment manualmente, como si alguien ejecutara
`kubectl delete` por accidente:

```bash
kubectl delete deployment grafana -n aiops
```

Salida esperada:
```
deployment.apps "grafana" deleted
```

### 3. Esperar la auto-recuperación

ArgoCD detecta el drift en ~3 minutos (intervalo de reconciliación
por defecto) y recrea el deployment:

```bash
# Esperar y verificar
sleep 180
kubectl get deployment grafana -n aiops
```

Salida esperada:
```
NAME      READY   UP-TO-DATE   AVAILABLE   AGE
grafana   1/1     1            1           10s
```

### 4. Ver el evento en el dashboard de ArgoCD

```bash
kubectl port-forward -n argocd svc/argocd-server 8080:80
```

Abrir [http://localhost:8080](http://localhost:8080) → login con `admin` / `6iqyvE3oDh99IHQt`.

En la aplicación `aiops-lab`:
- El historial muestra un sync automático iniciado por "automated"
- El motivo del sync dice "self-heal" o "drift detected"
- El deployment `grafana` aparece como `OutOfSync` → `Synced`

### 5. Evidencia para documentar

Hacer screenshot del dashboard de ArgoCD mostrando:
1. El evento de sync automático en el timeline
2. El deployment `grafana` restaurado
3. El estado `Synced` y `Healthy` después de la recuperación

## Qué demuestra esto

| Sin ArgoCD | Con ArgoCD selfHeal |
|---|---|
| `kubectl delete` = outage hasta intervención manual | `kubectl delete` = 3 min de outage, auto-recuperación |
| Git y cluster divergen sin que nadie lo sepa | Cluster siempre refleja Git |
| "Funciona en mi máquina" | "Funciona en Git" |

## Troubleshooting

Si el deployment no se restaura:

1. **Verificar que el controller esté corriendo:**
   ```bash
   kubectl get pods -n argocd | grep application-controller
   ```

2. **Verificar el estado de la aplicación:**
   ```bash
   kubectl get application aiops-lab -n argocd
   ```

3. **Forzar un refresh manual:**
   ```bash
   kubectl annotate application aiops-lab -n argocd --overwrite \
     argocd.argoproj.io/refresh=hard
   ```

4. **Revisar los logs del controller:**
   ```bash
   kubectl logs -n argocd -l app.kubernetes.io/name=argocd-application-controller --tail=50
   ```
