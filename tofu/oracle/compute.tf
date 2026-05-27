# ──────────────────────────────────────────────
# Compute Instances — vm-bastion + vm-k3s
# Fase 9: Migración a Oracle Cloud
# ──────────────────────────────────────────────
#
# Ampere A1 (ARM64): 4 OCPUs + 24 GB RAM total gratis.
#   vm-bastion → 1 OCPU + 6 GB
#   vm-k3s     → 3 OCPUs + 18 GB
#   Total      → 4 OCPUs + 24 GB = límite Free Tier exacto
#
# Boot volume total: 50 GB + 100 GB = 150 GB (límite: 200 GB)
# ──────────────────────────────────────────────

# ── Imagen de Rocky Linux 9 (ARM64) ──
data "oci_core_images" "rocky" {
  compartment_id           = var.compartment_id
  operating_system         = "Rocky Linux"
  operating_system_version = "9"
  shape                    = "VM.Standard.A1.Flex"
  sort_by                  = "TIMECREATED"
  sort_order               = "DESC"
}

# ── Cloud-init ──
data "cloudinit_config" "bastion" {
  gzip          = false
  base64_encode = true

  part {
    content_type = "text/cloud-config"
    content = templatefile("${path.module}/templates/cloud-init.yml.tmpl", {
      ssh_public_key = var.ssh_public_key
      hostname       = "bastion"
    })
  }
}

data "cloudinit_config" "k3s" {
  gzip          = false
  base64_encode = true

  part {
    content_type = "text/cloud-config"
    content = templatefile("${path.module}/templates/cloud-init.yml.tmpl", {
      ssh_public_key = var.ssh_public_key
      hostname       = "k3s"
    })
  }
}

# ── vm-bastion: 1 OCPU, 6 GB RAM ──
resource "oci_core_instance" "bastion" {
  compartment_id      = var.compartment_id
  availability_domain = data.oci_identity_availability_domains.ads.availability_domains[0].name
  display_name        = "vm-bastion"
  shape               = "VM.Standard.A1.Flex"

  shape_config {
    ocpus         = 1
    memory_in_gbs = 6
  }

  create_vnic_details {
    subnet_id        = oci_core_subnet.aiops.id
    assign_public_ip = true
    nsg_ids          = [oci_core_network_security_group.bastion.id]
  }

  source_details {
    source_type             = "image"
    source_id               = data.oci_core_images.rocky.images[0].id
    boot_volume_size_in_gbs = 50
  }

  metadata = {
    ssh_authorized_keys = var.ssh_public_key
    user_data           = data.cloudinit_config.bastion.rendered
  }

  lifecycle {
    ignore_changes = [
      metadata["user_data"],
      metadata["ssh_authorized_keys"],
      source_details[0].source_id,
    ]
  }
}

# ── vm-k3s: 3 OCPUs, 18 GB RAM ──
resource "oci_core_instance" "k3s" {
  compartment_id      = var.compartment_id
  availability_domain = data.oci_identity_availability_domains.ads.availability_domains[0].name
  display_name        = "vm-k3s"
  shape               = "VM.Standard.A1.Flex"

  shape_config {
    ocpus         = 3
    memory_in_gbs = 18
  }

  create_vnic_details {
    subnet_id        = oci_core_subnet.aiops.id
    assign_public_ip = true
    nsg_ids          = [oci_core_network_security_group.k3s.id]
  }

  source_details {
    source_type             = "image"
    source_id               = data.oci_core_images.rocky.images[0].id
    boot_volume_size_in_gbs = 100
  }

  metadata = {
    ssh_authorized_keys = var.ssh_public_key
    user_data           = data.cloudinit_config.k3s.rendered
  }

  lifecycle {
    ignore_changes = [
      metadata["user_data"],
      metadata["ssh_authorized_keys"],
      source_details[0].source_id,
    ]
  }
}
