#!/bin/bash
# ============================================================
# setup-vault.sh — Despliegue automatizado de HashiCorp Vault
# ============================================================
#
# Este script automatiza el despliegue completo de Vault:
#   1. Genera certificados TLS auto-firmados para el webhook
#   2. Crea el Secret con los certificados
#   3. Despliega Vault server, Injector, y Config Job
#   4. Espera a que todos los componentes estén listos
#   5. Configura Vault (Kubernetes auth, políticas, secrets)
#   6. Verifica la configuración
#
# Uso:
#   chmod +x k3s/manifests/vault/setup-vault.sh
#   ./k3s/manifests/vault/setup-vault.sh
#
# Prerrequisitos:
#   - kubectl configurado y apuntando al cluster k3s
#   - El namespace 'aiops' debe existir
#   - jq instalado (para verificar health checks)
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
NAMESPACE="aiops"

echo "=========================================="
echo "  HashiCorp Vault — Fase 3: Setup"
echo "=========================================="
echo ""

# ---- Colores para output ----
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

info()  { echo -e "${GREEN}[INFO]${NC}  $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

# ---- Paso 1: Generar certificados TLS para el webhook ----
info "Paso 1/6: Generando certificados TLS para el webhook del Injector..."

TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

# Generar clave CA y certificado
openssl genrsa -out "$TEMP_DIR/ca.key" 2048 2>/dev/null
openssl req -new -x509 \
  -key "$TEMP_DIR/ca.key" \
  -out "$TEMP_DIR/ca.crt" \
  -days 365 \
  -subj "/CN=vault-agent-injector-ca" 2>/dev/null

# Generar clave del servidor y CSR
openssl genrsa -out "$TEMP_DIR/tls.key" 2048 2>/dev/null

# Crear archivo de extensión para SANs
cat > "$TEMP_DIR/san.cnf" <<EOF
[req]
req_extensions = v3_req
distinguished_name = req_distinguished_name
[req_distinguished_name]
[v3_req]
subjectAltName = @alt_names
[alt_names]
DNS.1 = vault-agent-injector
DNS.2 = vault-agent-injector.aiops
DNS.3 = vault-agent-injector.aiops.svc
DNS.4 = vault-agent-injector.aiops.svc.cluster.local
EOF

openssl req -new \
  -key "$TEMP_DIR/tls.key" \
  -out "$TEMP_DIR/tls.csr" \
  -config "$TEMP_DIR/san.cnf" 2>/dev/null

# Firmar el certificado del servidor con la CA
openssl x509 -req \
  -in "$TEMP_DIR/tls.csr" \
  -CA "$TEMP_DIR/ca.crt" \
  -CAkey "$TEMP_DIR/ca.key" \
  -CAcreateserial \
  -out "$TEMP_DIR/tls.crt" \
  -days 365 \
  -extensions v3_req \
  -extfile "$TEMP_DIR/san.cnf" 2>/dev/null

# Crear el Secret de Kubernetes con los certificados
# Eliminar el Secret si ya existe (para permitir re-despliegue)
kubectl delete secret vault-agent-injector-tls -n "$NAMESPACE" --ignore-not-found=true 2>/dev/null

kubectl create secret generic vault-agent-injector-tls \
  --namespace="$NAMESPACE" \
  --from-file=tls.crt="$TEMP_DIR/tls.crt" \
  --from-file=tls.key="$TEMP_DIR/tls.key" \
  --from-file=ca.crt="$TEMP_DIR/ca.crt" 2>/dev/null

# Codificar el CA bundle para el MutatingWebhookConfiguration
CA_BUNDLE=$(cat "$TEMP_DIR/ca.crt" | base64 | tr -d '\n')

info "✓ Certificados TLS generados y Secret creado"

# ---- Paso 2: Desplegar Vault server ----
echo ""
info "Paso 2/6: Desplegando Vault server..."

kubectl apply -f "$SCRIPT_DIR/serviceaccount.yml"
kubectl apply -f "$SCRIPT_DIR/configmap.yml"
kubectl apply -f "$SCRIPT_DIR/deployment.yml"
kubectl apply -f "$SCRIPT_DIR/service.yml"

info "✓ Vault server desplegado"

# ---- Paso 3: Desplegar Vault Agent Injector ----
echo ""
info "Paso 3/6: Desplegando Vault Agent Injector..."

kubectl apply -f "$SCRIPT_DIR/injector-serviceaccount.yml"
kubectl apply -f "$SCRIPT_DIR/injector-service.yml"
kubectl apply -f "$SCRIPT_DIR/injector-deployment.yml"

# Parchear el MutatingWebhookConfiguration con el CA bundle
# Primero aplicar el webhook base (sin caBundle)
# Luego parchear con el CA bundle real
info "Configurando MutatingWebhookConfiguration con CA bundle..."
kubectl apply -f "$SCRIPT_DIR/mutating-webhook.yml"

# Parchear el webhook con el CA bundle generado
# El campo caBundle en el webhook debe contener el CA cert codificado en base64
kubectl patch mutatingwebhookconfiguration vault-agent-injector \
  --namespace="$NAMESPACE" \
  --type='json' \
  -p="[{\"op\": \"replace\", \"path\": \"/webhooks/0/clientConfig/caBundle\", \"value\":\"$CA_BUNDLE\"}]" 2>/dev/null || \
kubectl patch mutatingwebhookconfiguration vault-agent-injector \
  --namespace="$NAMESPACE" \
  --type='json' \
  -p="[{\"op\": \"add\", \"path\": \"/webhooks/0/clientConfig/caBundle\", \"value\":\"$CA_BUNDLE\"}]" 2>/dev/null || true

info "✓ Injector y webhook desplegados"

# ---- Paso 4: Esperar a que Vault esté listo ----
echo ""
info "Paso 4/6: Esperando a que Vault esté listo..."

kubectl wait --for=condition=ready pod -l app=vault \
  --namespace="$NAMESPACE" \
  --timeout=120s

info "✓ Vault está listo"

# ---- Paso 5: Ejecutar Job de configuración ----
echo ""
info "Paso 5/6: Configurando Vault (Kubernetes auth, políticas, secrets)..."

# Eliminar Job anterior si existe (para permitir re-ejecución)
kubectl delete job vault-config --namespace="$NAMESPACE" --ignore-not-found=true 2>/dev/null

kubectl apply -f "$SCRIPT_DIR/config-job.yml"

# Esperar a que el Job de configuración termine
kubectl wait --for=condition=complete job/vault-config \
  --namespace="$NAMESPACE" \
  --timeout=180s

info "✓ Vault configurado (Kubernetes auth, políticas, secrets)"

# ---- Paso 6: Verificación ----
echo ""
info "Paso 6/6: Verificando configuración..."

# Verificar que Vault responde
VAULT_POD=$(kubectl get pods -n "$NAMESPACE" -l app=vault -o jsonpath='{.items[0].metadata.name}')
VAULT_STATUS=$(kubectl exec -n "$NAMESPACE" "$VAULT_POD" -- vault status -format=json 2>/dev/null || echo '{}')

if echo "$VAULT_STATUS" | grep -q '"initialized": true'; then
  info "✓ Vault está inicializado"
else
  warn "No se pudo verificar el estado de Vault (esto es normal en modo dev)"
fi

# Verificar que los secrets existen
echo ""
info "Secrets almacenados en Vault:"
kubectl exec -n "$NAMESPACE" "$VAULT_POD" -- vault kv list secret/ 2>/dev/null || warn "No se pudieron listar los secrets"

echo ""
echo "=========================================="
echo -e "  ${GREEN}✓ Vault desplegado y configurado!${NC}"
echo "=========================================="
echo ""
echo "Servicios desplegados:"
echo "  - Vault Server:    http://vault.aiops.svc.cluster.local:8200"
echo "  - Vault Injector:  https://vault-agent-injector.aiops.svc.cluster.local:443"
echo ""
echo "Próximos pasos:"
echo "  1. Redesplegar Grafana con annotations de Vault Agent:"
echo "     kubectl apply -f k3s/manifests/grafana/"
echo ""
echo "  2. Redesplegar n8n con annotations de Vault Agent:"
echo "     kubectl apply -f k3s/manifests/n8n/"
echo ""
echo "  3. Verificar que los pods leen secrets de Vault:"
echo "     kubectl logs -n aiops -l app=grafana -c vault-agent-init"
echo "     kubectl logs -n aiops -l app=n8n -c vault-agent-init"
echo ""
echo "Para acceder a la UI de Vault (port-forward):"
echo "  kubectl port-forward -n aiops svc/vault 8200:8200"
echo "  Abrir http://localhost:8200 (token: dev-root-token)"
