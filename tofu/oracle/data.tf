# ──────────────────────────────────────────────
# Data Sources — Oracle Cloud (OCI)
# Fase 9: Migración a Oracle Cloud
# ──────────────────────────────────────────────

# ── Availability Domains ──
data "oci_identity_availability_domains" "ads" {
  compartment_id = var.tenancy_ocid
}

# ── Object Storage Namespace (valor único por tenancy) ──
data "oci_objectstorage_namespace" "aiops" {
  compartment_id = var.compartment_id
}
