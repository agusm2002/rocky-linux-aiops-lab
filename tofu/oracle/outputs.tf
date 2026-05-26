# ──────────────────────────────────────────────
# Outputs — OCI Network Security Groups
# ──────────────────────────────────────────────

output "nsg_bastion_id" {
  description = "OCID del NSG del bastion"
  value       = oci_core_network_security_group.bastion.id
}

output "nsg_k3s_id" {
  description = "OCID del NSG de k3s"
  value       = oci_core_network_security_group.k3s.id
}
