# ──────────────────────────────────────────────
# Networking — VCN, Subnet, Internet Gateway
# Fase 9: Migración a Oracle Cloud
# ──────────────────────────────────────────────
#
# Free Tier no incluye NAT Gateway gratis. Ambas VMs van en
# subnet pública protegida por NSG: el bastion solo acepta SSH
# desde tu IP, y k3s solo desde el bastion. Esto es seguro
# para un lab y mantiene el costo real en $0.
# ──────────────────────────────────────────────

# ── VCN ──
resource "oci_core_vcn" "aiops" {
  compartment_id = var.compartment_id
  cidr_blocks    = ["10.0.0.0/16"]
  display_name   = "vcn-aiops-lab"
  dns_label      = "aiops"
}

# ── Internet Gateway ──
resource "oci_core_internet_gateway" "aiops" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.aiops.id
  display_name   = "igw-aiops"
}

# ── Default Route Table: tráfico público via IGW ──
resource "oci_core_default_route_table" "aiops" {
  manage_default_resource_id = oci_core_vcn.aiops.default_route_table_id

  route_rules {
    destination       = "0.0.0.0/0"
    network_entity_id = oci_core_internet_gateway.aiops.id
  }
}

# ── Subnet pública ──
resource "oci_core_subnet" "aiops" {
  compartment_id             = var.compartment_id
  vcn_id                     = oci_core_vcn.aiops.id
  cidr_block                 = "10.0.1.0/24"
  display_name               = "subnet-aiops"
  dns_label                  = "aiopssubnet"
  prohibit_public_ip_on_vnic = false
  route_table_id             = oci_core_default_route_table.aiops.id
}
