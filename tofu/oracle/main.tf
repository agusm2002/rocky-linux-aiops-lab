# ──────────────────────────────────────────────
# Network Security Groups — Oracle Cloud (OCI)
# Fase 9: Migración a Oracle Cloud
# ──────────────────────────────────────────────
#
# Principio de least-privilege: solo se abren los puertos
# estrictamente necesarios. Todo lo demás está bloqueado.
#
# El provider y el bloque terraform están en provider.tf
# ──────────────────────────────────────────────

# ── NSG: Bastion ──

resource "oci_core_network_security_group" "bastion" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.aiops.id
  display_name   = "nsg-bastion"
}

# SSH solo desde tu IP pública
resource "oci_core_network_security_group_security_rule" "bastion_ssh" {
  network_security_group_id = oci_core_network_security_group.bastion.id
  direction                 = "INGRESS"
  protocol                  = "6"
  source                    = var.admin_cidr
  source_type               = "CIDR_BLOCK"

  tcp_options {
    destination_port_range {
      min = 22
      max = 22
    }
  }
}

# ──────────────────────────────────────────────
# NSG: k3s
# ──────────────────────────────────────────────

resource "oci_core_network_security_group" "k3s" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.aiops.id
  display_name   = "nsg-k3s"
}

# HTTPS desde internet — demo pública (Grafana + apps)
resource "oci_core_network_security_group_security_rule" "k3s_https" {
  network_security_group_id = oci_core_network_security_group.k3s.id
  direction                 = "INGRESS"
  protocol                  = "6"
  source                    = "0.0.0.0/0"
  source_type               = "CIDR_BLOCK"

  tcp_options {
    destination_port_range {
      min = 443
      max = 443
    }
  }
}

# HTTP → redirect a HTTPS (necesario para el challenge Let's Encrypt si se usa)
resource "oci_core_network_security_group_security_rule" "k3s_http" {
  network_security_group_id = oci_core_network_security_group.k3s.id
  direction                 = "INGRESS"
  protocol                  = "6"
  source                    = "0.0.0.0/0"
  source_type               = "CIDR_BLOCK"

  tcp_options {
    destination_port_range {
      min = 80
      max = 80
    }
  }
}

# SSH solo desde IP privada del bastion
resource "oci_core_network_security_group_security_rule" "k3s_ssh" {
  network_security_group_id = oci_core_network_security_group.k3s.id
  direction                 = "INGRESS"
  protocol                  = "6"
  source                    = oci_core_instance.bastion.private_ip
  source_type               = "CIDR_BLOCK"

  tcp_options {
    destination_port_range {
      min = 22
      max = 22
    }
  }
}

# k3s API — solo desde el bastion
resource "oci_core_network_security_group_security_rule" "k3s_api" {
  network_security_group_id = oci_core_network_security_group.k3s.id
  direction                 = "INGRESS"
  protocol                  = "6"
  source                    = oci_core_instance.bastion.private_ip
  source_type               = "CIDR_BLOCK"

  tcp_options {
    destination_port_range {
      min = 6443
      max = 6443
    }
  }
}

# NodePorts internos — solo desde el bastion (acceso administrativo)
resource "oci_core_network_security_group_security_rule" "k3s_nodeports" {
  network_security_group_id = oci_core_network_security_group.k3s.id
  direction                 = "INGRESS"
  protocol                  = "6"
  source                    = oci_core_instance.bastion.private_ip
  source_type               = "CIDR_BLOCK"

  tcp_options {
    destination_port_range {
      min = 30000
      max = 32767
    }
  }
}

# Egress — permitir todo (las VMs necesitan acceder a internet para updates, git, etc.)
resource "oci_core_network_security_group_security_rule" "bastion_egress" {
  network_security_group_id = oci_core_network_security_group.bastion.id
  direction                 = "EGRESS"
  protocol                  = "all"
  destination               = "0.0.0.0/0"
  destination_type          = "CIDR_BLOCK"
}

resource "oci_core_network_security_group_security_rule" "k3s_egress" {
  network_security_group_id = oci_core_network_security_group.k3s.id
  direction                 = "EGRESS"
  protocol                  = "all"
  destination               = "0.0.0.0/0"
  destination_type          = "CIDR_BLOCK"
}
