output "public_ip" {
  description = "Public IP address of the VM"
  # Point to the instance directly since the EIP was removed
  value       = aws_instance.epicbook.public_ip
}

output "admin_user" {
  description = "Admin username for SSH access"
  value       = var.admin_username
}

output "ssh_access_command" {
  description = "SSH command to access the VM"
  value       = "ssh ${var.admin_username}@${aws_instance.epicbook.public_ip}"
}

output "rds_endpoint" {
  description = "The endpoint of the RDS instance"
  value       = aws_db_instance.epicbook_db.endpoint
}
