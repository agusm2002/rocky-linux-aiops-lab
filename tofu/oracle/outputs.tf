# ──────────────────────────────────────────────
# Outputs — Oracle Cloud (OCI)
# Fase 9: Migración a Oracle Cloud
# ──────────────────────────────────────────────

# NSGs
output "nsg_bastion_id" {
  description = "OCID del NSG del bastion"
  value       = oci_core_network_security_group.bastion.id
}

output "nsg_k3s_id" {
  description = "OCID del NSG de k3s"
  value       = oci_core_network_security_group.k3s.id
}

# VCN
output "vcn_id" {
  description = "OCID de la VCN"
  value       = oci_core_vcn.aiops.id
}

output "subnet_id" {
  description = "OCID de la subnet pública"
  value       = oci_core_subnet.aiops.id
}

# Compute — IPs
output "bastion_public_ip" {
  description = "IP pública del bastion (único punto de entrada SSH)"
  value       = oci_core_instance.bastion.public_ip
}

output "bastion_private_ip" {
  description = "IP privada del bastion"
  value       = oci_core_instance.bastion.private_ip
}

output "k3s_public_ip" {
  description = "IP pública de vm-k3s (Grafana demo)"
  value       = oci_core_instance.k3s.public_ip
}

output "k3s_private_ip" {
  description = "IP privada de vm-k3s"
  value       = oci_core_instance.k3s.private_ip
}

# Object Storage
output "loki_bucket_name" {
  description = "Nombre del bucket de Loki"
  value       = oci_objectstorage_bucket.loki.name
}

output "loki_bucket_namespace" {
  description = "Namespace del Object Storage"
  value       = oci_objectstorage_bucket.loki.namespace
}

# Vault
output "vault_id" {
  description = "OCID del OCI Vault"
  value       = oci_kms_vault.aiops.id
}

output "vault_management_endpoint" {
  description = "Endpoint de gestión del Vault"
  value       = oci_kms_vault.aiops.management_endpoint
}
