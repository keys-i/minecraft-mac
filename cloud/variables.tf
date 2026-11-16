variable "compartment_ocid" {
  type = string
  validation {
    condition     = startswith(var.compartment_ocid, "ocid1.compartment.")
    error_message = "Choose an OCI compartment OCID"
  }
}

variable "availability_domain" {
  type = string
}

variable "vcn_ocid" {
  type = string
}

variable "subnet_ocid" {
  type = string
}

variable "image_ocid" {
  type        = string
  description = "Hardened Linux GPU image with NVIDIA/VAAPI, Vulkan, Gamescope, FFmpeg, MediaMTX and Caddy"
}

variable "shape" {
  type    = string
  default = "VM.GPU.A10.1"
}

variable "boot_volume_gb" {
  type    = number
  default = 200
  validation {
    condition     = var.boot_volume_gb >= 100
    error_message = "The game host needs at least 100 GB"
  }
}

variable "hostname" {
  type = string
  validation {
    condition     = can(regex("^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?(?:\\.[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?)+$", var.hostname))
    error_message = "Choose a lowercase DNS hostname"
  }
}

variable "admin_cidr" {
  type        = string
  description = "Single trusted administration network such as 203.0.113.8/32"
  validation {
    condition     = can(cidrnetmask(var.admin_cidr)) && var.admin_cidr != "0.0.0.0/0"
    error_message = "SSH must be restricted to a trusted CIDR"
  }
}

variable "ssh_public_key" {
  type      = string
  sensitive = true
}

variable "ssh_private_key_path" {
  type = string
}

variable "ssh_user" {
  type    = string
  default = "ubuntu"
}

variable "stream_binary" {
  type        = string
  description = "Path to the x86_64 Linux MinecraftStream release binary"
}

variable "encoder" {
  type    = string
  default = "cuda"
  validation {
    condition     = contains(["cuda", "vaapi"], var.encoder)
    error_message = "Encoder must be cuda or vaapi"
  }
}

variable "mediamtx_version" {
  type    = string
  default = "v1.15.4"
  validation {
    condition     = can(regex("^v[0-9]+\\.[0-9]+\\.[0-9]+$", var.mediamtx_version))
    error_message = "MediaMTX version must use vMAJOR.MINOR.PATCH"
  }
}
