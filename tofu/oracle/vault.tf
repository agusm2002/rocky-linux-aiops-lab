# ──────────────────────────────────────────────
# OCI Vault — Secrets gestionados
# Fase 9: Migración a Oracle Cloud
# ──────────────────────────────────────────────
#
# Free Tier: 20 key versions + 150 secrets.
# Los secrets se crean con placeholder y se pueblan
# manualmente post-apply desde la consola o CLI.
#
# NOTA: La IAM policy para Instance Principal se configura
# manualmente en la consola OCI post-apply. Es una sola
# vez y evita complejidad innecesaria en OpenTofu.
# Ver docs/fase-9-migracion-oracle-cloud.md Paso 7.
# ──────────────────────────────────────────────

resource "oci_kms_vault" "aiops" {
  compartment_id = var.compartment_id
  display_name   = "vault-aiops-lab"
  vault_type     = "DEFAULT"
}

resource "oci_kms_key" "aiops" {
  compartment_id      = var.compartment_id
  display_name        = "key-aiops-lab"
  management_endpoint = oci_kms_vault.aiops.management_endpoint
  key_shape {
    algorithm = "AES"
    length    = 32
  }
}

# Los secrets usan BASE64 para cumplir con la API de OCI.
# "Q0hBTkdFX01F" = base64 de "CHANGE_ME" (placeholder).
# Se reemplazan post-apply desde la consola OCI → Vault → Secrets.

resource "oci_vault_secret" "n8n_encryption_key" {
  compartment_id = var.compartment_id
  vault_id       = oci_kms_vault.aiops.id
  key_id         = oci_kms_key.aiops.id
  secret_name    = "n8n-encryption-key"
  secret_content {
    content_type = "BASE64"
    content      = "Q0hBTkdFX01FX0FGVEVSX0FQUExZ" # CHANGE_ME_AFTER_APPLY
  }
}

resource "oci_vault_secret" "grafana_admin_password" {
  compartment_id = var.compartment_id
  vault_id       = oci_kms_vault.aiops.id
  key_id         = oci_kms_key.aiops.id
  secret_name    = "grafana-admin-password"
  secret_content {
    content_type = "BASE64"
    content      = "Q0hBTkdFX01FX0FGVEVSX0FQUExZ"
  }
}

resource "oci_vault_secret" "discord_webhook" {
  compartment_id = var.compartment_id
  vault_id       = oci_kms_vault.aiops.id
  key_id         = oci_kms_key.aiops.id
  secret_name    = "discord-webhook-url"
  secret_content {
    content_type = "BASE64"
    content      = "Q0hBTkdFX01FX0FGVEVSX0FQUExZ"
  }
}
