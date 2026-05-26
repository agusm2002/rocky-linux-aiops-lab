# ──────────────────────────────────────────────
# Variables — Oracle Cloud (OCI) NSG
# Fase 8: Seguridad para Producción
# ──────────────────────────────────────────────

variable "region" {
  description = "Región de OCI (ej: us-ashburn-1, sa-saopaulo-1)"
  type        = string
  default     = "us-ashburn-1"
}

variable "tenancy_ocid" {
  description = "OCID del tenancy en OCI"
  type        = string
  sensitive   = true
}

variable "user_ocid" {
  description = "OCID del usuario OCI"
  type        = string
  sensitive   = true
}

variable "private_key_path" {
  description = "Ruta a la clave privada de la API key de OCI"
  type        = string
  default     = "~/.oci/oci_api_key.pem"
}

variable "fingerprint" {
  description = "Fingerprint de la API key de OCI"
  type        = string
  sensitive   = true
}

variable "compartment_id" {
  description = "OCID del compartment donde se crean los recursos"
  type        = string
}

variable "vcn_id" {
  description = "OCID de la VCN existente"
  type        = string
}

variable "admin_cidr" {
  description = "Tu IP pública con /32 para acceso SSH al bastion"
  type        = string
  default     = "0.0.0.0/32"
  # ⚠️  Cambiar a tu IP real antes del apply
  # Ejemplo: "203.0.113.45/32"
}
