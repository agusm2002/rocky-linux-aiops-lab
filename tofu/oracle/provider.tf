# ──────────────────────────────────────────────
# OpenTofu Provider — Oracle Cloud (OCI)
# Fase 9: Migración a Oracle Cloud
# ──────────────────────────────────────────────

terraform {
  required_version = ">= 1.7"

  required_providers {
    oci = {
      source  = "oracle/oci"
      version = "~> 6.0"
    }
  }
}

provider "oci" {
  region           = var.region
  tenancy_ocid     = var.tenancy_ocid
  user_ocid        = var.user_ocid
  private_key_path = var.private_key_path
  fingerprint      = var.fingerprint
}
