# ──────────────────────────────────────────────
# OCI Object Storage — Backend de Loki
# Fase 9: Migración a Oracle Cloud
# ──────────────────────────────────────────────
#
# Free Tier: 10 GB/mes de almacenamiento.
# Loki con retention de 31 días y lab de baja carga
# queda muy por debajo de ese límite.
# ──────────────────────────────────────────────

resource "oci_objectstorage_bucket" "loki" {
  compartment_id = var.compartment_id
  name           = "loki-aiops-lab"
  namespace      = data.oci_objectstorage_namespace.aiops.namespace
  access_type    = "NoPublicAccess"
  storage_tier   = "Standard"
}
