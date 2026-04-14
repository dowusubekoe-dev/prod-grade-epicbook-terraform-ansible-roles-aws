variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "admin_username" {
  description = "Admin username for Ubuntu VM"
  type        = string
  default     = "ubuntu"
}

variable "private_key_path" {
  description = "Path to private keypair file (public key should be at path + '.pub')"
  type        = string
  default     = "~/.ssh/id_ed25519"
}

variable "ami_id" {
  description = "Ubuntu 22.04 LTS AMI ID for the selected region (us-east-1)"
  type        = string
  default     = "ami-0ec10929233384c7f"
}

variable "db_password" {
  description = "RDS MySQL root password — set via terraform.tfvars or TF_VAR_db_password env var"
  type        = string
  sensitive   = true
}
