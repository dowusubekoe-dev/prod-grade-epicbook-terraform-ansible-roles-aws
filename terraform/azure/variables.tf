variable "subscription_id" {
  description = "Azure subscription ID"
  type        = string
}

variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
  default     = "epicbook-rg"
}

variable "location" {
  description = "Azure region"
  type        = string
  default     = "eastus"
}

variable "admin_username" {
  description = "Admin username for Ubuntu VM"
  type        = string
  default     = "ubuntu"
}

variable "private_key_path" {
  description = "Path to SSH private key (public key should be at path + '.pub')"
  type        = string
  default     = "~/.ssh/id_ed25519"
}

variable "mysql_password" {
  description = "Azure Database for MySQL admin password"
  type        = string
  sensitive   = true
}

variable "vm_size" {
  description = "Azure VM size"
  type        = string
  default     = "Standard_B1s"
}
