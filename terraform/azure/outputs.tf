output "public_ip" {
  description = "Public IP address of the VM"
  value       = azurerm_public_ip.vm_public_ip.ip_address
}

output "admin_user" {
  description = "Admin username for SSH access"
  value       = var.admin_username
}

output "ssh_access_command" {
  description = "SSH command to access the VM"
  value       = "ssh ${var.admin_username}@${azurerm_public_ip.vm_public_ip.ip_address}"
}

output "mysql_endpoint" {
  description = "The endpoint of the Azure Database for MySQL"
  value       = azurerm_mysql_flexible_server.epicbook.fqdn
}

output "mysql_fqdn" {
  description = "MySQL fully qualified domain name (without port)"
  value       = azurerm_mysql_flexible_server.epicbook.fqdn
}

output "resource_group_name" {
  description = "Name of the resource group"
  value       = azurerm_resource_group.main.name
}
