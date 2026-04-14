# Resource Group
resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location
}

# Virtual Network
resource "azurerm_virtual_network" "main" {
  name                = "epicbook-vnet"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
}

# Subnet 1 (for VM)
resource "azurerm_subnet" "vm_subnet" {
  name                 = "epicbook-vm-subnet"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.0.1.0/24"]
}

# Subnet 2 (for MySQL delegation - required for private endpoints)
resource "azurerm_subnet" "mysql_subnet" {
  name                 = "epicbook-mysql-subnet"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.0.2.0/24"]

  delegation {
    name = "fs"
    service_delegation {
      name = "Microsoft.DBforMySQL/flexibleServers"
      actions = [
        "Microsoft.Network/virtualNetworks/subnets/join/action",
      ]
    }
  }
}

# Network Security Group for VM
resource "azurerm_network_security_group" "vm_nsg" {
  name                = "epicbook-vm-nsg"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  security_rule {
    name                       = "AllowSSH"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "AllowHTTP"
    priority                   = 1002
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  tags = {
    Name = "epicbook-vm-nsg"
  }
}

# Public IP for VM
resource "azurerm_public_ip" "vm_public_ip" {
  name                = "epicbook-vm-public-ip"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  allocation_method   = "Dynamic"
  sku                 = "Basic"
}

# Network Interface for VM
resource "azurerm_network_interface" "vm_nic" {
  name                = "epicbook-vm-nic"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.vm_subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.vm_public_ip.id
  }
}

# NSG Association with NIC
resource "azurerm_network_interface_security_group_association" "nsg_association" {
  network_interface_id      = azurerm_network_interface.vm_nic.id
  network_security_group_id = azurerm_network_security_group.vm_nsg.id
}

# SSH Key Pair (read public key from local file)
resource "azurerm_ssh_public_key" "epicbook" {
  name                = "epicbook-ssh-key"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  public_key          = file("${var.private_key_path}.pub")
}

# Ubuntu VM
resource "azurerm_linux_virtual_machine" "epicbook" {
  name                = "epicbook-vm"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  size                = var.vm_size
  admin_username      = var.admin_username
  network_interface_ids = [
    azurerm_network_interface.vm_nic.id,
  ]

  admin_ssh_key {
    username   = var.admin_username
    public_key = file("${var.private_key_path}.pub")
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
    disk_size_gb         = 30
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts"
    version   = "latest"
  }

  tags = {
    Name = "epicbook-vm"
  }
}

# MySQL Server (Azure Database for MySQL - Flexible Server)
resource "azurerm_mysql_flexible_server" "epicbook" {
  name                = "epicbook-mysql"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  administrator_login = "adminuser"
  administrator_password = var.mysql_password

  sku_name   = "B_Standard_B1ms"
  storage_mb = 20480
  version    = "8.0"

  delegation_subnet_id = azurerm_subnet.mysql_subnet.id

  high_availability {
    mode = "Disabled"
  }

  tags = {
    Name = "epicbook-mysql"
  }
}

# MySQL Firewall Rule - Allow VM subnet to access MySQL
resource "azurerm_mysql_flexible_server_firewall_rule" "allow_vm_subnet" {
  name                = "AllowVMS subnet"
  server_id           = azurerm_mysql_flexible_server.epicbook.id
  start_ip_address    = cidrhost(azurerm_subnet.vm_subnet.address_prefixes[0], 0)
  end_ip_address      = cidrhost(azurerm_subnet.vm_subnet.address_prefixes[0], -1)
}
