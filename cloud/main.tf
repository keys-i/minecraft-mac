terraform {
  required_version = ">= 1.8.0"

  required_providers {
    oci = {
      source  = "oracle/oci"
      version = ">= 6.0.0, < 8.0.0"
    }
  }
}

provider "oci" {}

resource "oci_core_network_security_group" "stream" {
  compartment_id = var.compartment_ocid
  vcn_id         = var.vcn_ocid
  display_name   = "minecraft-stream"
}

resource "oci_core_network_security_group_security_rule" "https" {
  network_security_group_id = oci_core_network_security_group.stream.id
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

resource "oci_core_network_security_group_security_rule" "webrtc" {
  network_security_group_id = oci_core_network_security_group.stream.id
  direction                 = "INGRESS"
  protocol                  = "17"
  source                    = "0.0.0.0/0"
  source_type               = "CIDR_BLOCK"

  udp_options {
    destination_port_range {
      min = 8189
      max = 8189
    }
  }
}

resource "oci_core_network_security_group_security_rule" "ssh" {
  network_security_group_id = oci_core_network_security_group.stream.id
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

resource "oci_core_network_security_group_security_rule" "egress" {
  network_security_group_id = oci_core_network_security_group.stream.id
  direction                 = "EGRESS"
  protocol                  = "all"
  destination               = "0.0.0.0/0"
  destination_type          = "CIDR_BLOCK"
}

resource "oci_core_instance" "stream" {
  availability_domain = var.availability_domain
  compartment_id      = var.compartment_ocid
  display_name        = "minecraft-stream"
  shape               = var.shape

  create_vnic_details {
    assign_public_ip = true
    hostname_label   = "minecraft-stream"
    nsg_ids          = [oci_core_network_security_group.stream.id]
    subnet_id        = var.subnet_ocid
  }

  metadata = {
    ssh_authorized_keys = var.ssh_public_key
  }

  source_details {
    source_id               = var.image_ocid
    source_type             = "image"
    boot_volume_size_in_gbs = var.boot_volume_gb
  }

  preserve_boot_volume = true
}

resource "terraform_data" "deploy" {
  triggers_replace = [
    filesha256(var.stream_binary),
    filesha256("${path.module}/install"),
    filesha256("${path.module}/Caddyfile"),
    filesha256("${path.module}/mediamtx.yml"),
    filesha256("${path.module}/host.service"),
    filesha256("${path.module}/game.service"),
    filesha256("${path.module}/media.service"),
    var.hostname,
    var.encoder,
    var.mediamtx_version,
  ]

  connection {
    type        = "ssh"
    host        = oci_core_instance.stream.public_ip
    user        = var.ssh_user
    private_key = file(var.ssh_private_key_path)
  }

  provisioner "file" {
    source      = var.stream_binary
    destination = "/tmp/MinecraftStream"
  }

  provisioner "remote-exec" {
    inline = ["mkdir -p /tmp/minecraft-cloud"]
  }

  provisioner "file" {
    source      = "${path.module}/install"
    destination = "/tmp/minecraft-cloud/install"
  }

  provisioner "file" {
    source      = "${path.module}/Caddyfile"
    destination = "/tmp/minecraft-cloud/Caddyfile"
  }

  provisioner "file" {
    source      = "${path.module}/mediamtx.yml"
    destination = "/tmp/minecraft-cloud/mediamtx.yml"
  }

  provisioner "file" {
    source      = "${path.module}/host.service"
    destination = "/tmp/minecraft-cloud/host.service"
  }

  provisioner "file" {
    source      = "${path.module}/game.service"
    destination = "/tmp/minecraft-cloud/game.service"
  }

  provisioner "file" {
    source      = "${path.module}/media.service"
    destination = "/tmp/minecraft-cloud/media.service"
  }

  provisioner "remote-exec" {
    inline = [
      "chmod +x /tmp/minecraft-cloud/install",
      "sudo /tmp/minecraft-cloud/install '${var.hostname}' '${var.encoder}' '${var.mediamtx_version}'",
    ]
  }
}
