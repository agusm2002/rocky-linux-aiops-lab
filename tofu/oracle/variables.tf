# ──────────────────────────────────────────────
# Variables — Oracle Cloud (OCI)
# Fase 9: Migración a Oracle Cloud
# ──────────────────────────────────────────────

variable "region" {
  description = "Región de OCI"
  type        = string
  default     = "sa-saopaulo-1" # Brazil East
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
  description = "OCID del compartment aiops-lab"
  type        = string
}

variable "compartment_name" {
  description = "Nombre del compartment (para policies IAM)"
  type        = string
  default     = "aiops-lab"
}

variable "ssh_public_key" {
  description = "Clave SSH pública para acceso a las VMs"
  type        = string
  # Ejemplo: "ssh-ed25519 AAAAC3..."
}

variable "admin_cidr" {
  description = "Tu IP pública con /32 para acceso SSH al bastion"
  type        = string
  # ⚠️  Cambiar a tu IP real antes del apply
  # Ejemplo: "203.0.113.45/32"
}
