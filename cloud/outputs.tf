output "public_ip" {
  value = oci_core_instance.stream.public_ip
}

output "session_link_command" {
  value = "ssh ${var.ssh_user}@${oci_core_instance.stream.public_ip} sudo minecraft-stream-link"
}
