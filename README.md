# EpicBook — Production Deployment on Azure

A production-grade deployment of the [EpicBook](https://github.com/pravinmishraaws/theepicbook) Node.js/Express bookstore application using **Terraform** for Azure infrastructure provisioning and **Ansible roles** for configuration management.

---

## Architecture

```
                        ┌─────────────────────────────────────────┐
                        │         Azure East US                   │
                        │                                         │
                        │  ┌──────────────────────────────────┐   │
                        │  │     VNet  10.0.0.0/16            │   │
                        │  │                                  │   │
                        │  │  ┌────────────┐ ┌─────────────┐  │   │
                        │  │  │ VM Subnet  │ │ MySQL Subnet│  │   │
                        │  │  │ 10.0.1.0/24│ │ 10.0.2.0/24 │  │   │
                        │  │  │            │ │ (delegated) │  │   │
                        │  │  │ ┌────────┐ │ │ ┌─────────┐ │  │   │
                        │  │  │ │  VM    │ │ │ │  MySQL  │ │  │   │
                        │  │  │ │B1s, 1GB│ │ │ │Flexible │ │  │   │
                        │  │  │ │Ubuntu  │ │ │ │Server 8 │ │  │   │
                        │  │  │ └────────┘ │ │ └─────────┘ │  │   │
                        │  │  └────────────┘ └─────────────┘  │   │
                        │  │         │              │         │   │
                        │  │   NSG: 22,80    VNet private     │   │
                        │  │    (public)        access only   │   │
                        │  └──────────────────────────────────┘   │
                        └─────────────────────────────────────────┘
                                        │
                               Browser → port 80
                               SSH    → port 22
```

**Request flow:**
```
Browser → nginx (port 80) → Node.js / epicbook service (port 3000) → MySQL
                ↓
         /assets/* served directly from disk
```

---

## Project Structure

```
epicbook-prod/
├── terraform/
│   └── azure/                 # Azure infrastructure
│       ├── provider.tf        # Azure provider configuration
│       ├── main.tf            # Resource group, VNet, subnets, NSG, VM, MySQL
│       ├── variables.tf       # Input variables (subscription, location, VM size, MySQL password)
│       ├── output.tf          # Outputs: public_ip, admin_user, mysql_endpoint
│       └── terraform.tfvars   # Variable overrides
├── ansible/
│   ├── inventory.ini          # VM public IP + SSH config (update after apply)
│   ├── site.yml               # Playbook: common → nginx → epicbook
│   ├── ansible.cfg            # Ansible settings (pipelining, timeouts, etc.)
│   ├── group_vars/
│   │   └── web.yml            # Shared variables: repo, paths, DB credentials
│   └── roles/
│       ├── common/
│       │   ├── tasks/main.yml   # apt update, baseline packages, SSH hardening
│       │   └── handlers/main.yml
│       ├── nginx/
│       │   ├── tasks/main.yml   # Install nginx, deploy config, enable site
│       │   ├── templates/
│       │   │   └── epicbook.conf.j2  # Reverse proxy + static asset serving
│       │   └── handlers/main.yml
│       └── epicbook/
│           ├── tasks/main.yml   # Clone repo, npm install, DB seed, systemd service
│           ├── templates/
│           │   ├── epicbook.service.j2  # systemd unit (runs node server.js)
│           │   └── config.json.j2       # Sequelize DB config
│           └── handlers/main.yml
├── .pre-commit-config.yaml      # yamllint + ansible-lint hooks
├── .editorconfig
└── README.md
```

---

## Prerequisites

| Tool | Version | Purpose |
|---|---|---|
| Terraform | >= 1.5 | Infrastructure provisioning |
| Ansible | >= 2.14 | Configuration management |
| Python | >= 3.10 | Ansible runtime |
| Azure CLI | >= 2.x | Azure authentication |
| SSH key pair | ed25519 | VM access |

**Azure CLI authenticated:**
```bash
az login                          # interactive login
az account show                   # verify subscription
az account set --subscription "<SUB_ID>"  # if multiple subscriptions
```

**SSH key pair exists:**
```bash
ls ~/.ssh/id_ed25519 ~/.ssh/id_ed25519.pub
```

If you don't have one:
```bash
ssh-keygen -t ed25519 -C "epicbook-deploy"
```

**Python virtual environment (for Ansible and linting):**
```bash
cd ansible/
python3 -m venv .venv
source .venv/bin/activate
pip install ansible ansible-lint yamllint
```

---

## Step 1 — Provision Infrastructure with Terraform

### AWS Deployment

```bash
cd terraform/aws/
terraform init
terraform plan
terraform apply
```

Note the outputs after apply:

```
public_ip         = "x.x.x.x"
admin_user        = "ubuntu"
rds_endpoint      = "terraform-xxx.co16s6q6g4t2.us-east-1.rds.amazonaws.com:3306"
ssh_access_command = "ssh ubuntu@x.x.x.x"
```

> RDS provisioning takes 5–10 minutes. Terraform waits for it automatically.

### Azure Deployment

```bash
cd terraform/azure/
terraform init
terraform plan
terraform apply
```

Note the outputs after apply:

```
public_ip         = "x.x.x.x"
admin_user        = "ubuntu"
mysql_endpoint    = "epicbook-mysql.mysql.database.azure.com"
ssh_access_command = "ssh ubuntu@x.x.x.x"
```

> Azure MySQL Flexible Server provisioning takes 5–10 minutes. Terraform waits for it automatically.

---

## Step 2 — Update Ansible with Infrastructure Values

After `terraform apply`, update two files with the output values:

### AWS

**`ansible/inventory.ini`** — replace the IP with `public_ip`:
```ini
[web]
x.x.x.x

[web:vars]
ansible_user=ubuntu
ansible_ssh_private_key_file=~/.ssh/id_ed25519
```

**`ansible/group_vars/web.yml`** — replace `db_host` with the RDS endpoint (strip the `:3306` port suffix):
```yaml
db_host: "terraform-xxx.co16s6q6g4t2.us-east-1.rds.amazonaws.com"
```

### Azure

**`ansible/inventory.ini`** — replace the IP with `public_ip`:
```ini
[web]
x.x.x.x

[web:vars]
ansible_user=ubuntu
ansible_ssh_private_key_file=~/.ssh/id_ed25519
```

**`ansible/group_vars/web.yml`** — replace `db_host` with the MySQL endpoint (strip the `:3306` port suffix if present):
```yaml
db_host: "epicbook-mysql.mysql.database.azure.com"
```

> Note: Azure MySQL Flexible Server uses port 3306 by default. The `db_port` in `group_vars/web.yml` should remain `3306`.

---

## Step 3 — Test SSH Access

```bash
ssh ubuntu@<public_ip> 'hostname'
```

Expected output:
- **AWS**: The EC2 private hostname (e.g. `ip-10-0-1-145`)
- **Azure**: The VM hostname (e.g. `epicbook-vm`)

If this works, Ansible can connect.

---

## Step 4 — Run the Ansible Playbook

```bash
cd ansible/
ansible-playbook -i inventory.ini site.yml
```

The playbook runs three plays in order:

| Play | Role | What it does |
|---|---|---|
| Prepare system | `common` | apt update, install git/curl/unzip, SSH hardening |
| Configure Nginx | `nginx` | Install nginx, deploy reverse proxy config, enable site |
| Deploy EpicBook | `epicbook` | Clone repo, npm install, DB schema + seed, systemd service |

### What Ansible automates end-to-end

1. System updates and baseline package installation
2. SSH hardening (disable root login, disable password auth)
3. Nginx installed and configured as a reverse proxy to Node.js on port 3000
4. Static assets (`/assets/*`) served directly by nginx from disk
5. EpicBook repo cloned to `/var/www/epicbook`
6. npm dependencies installed
7. Sequelize `config/config.json` deployed with database connection details
8. Database schema created (only on first run — idempotent check)
9. Author and book seed data imported (only if empty — idempotent check)
10. `epicbook` systemd service created, started, and enabled
11. File ownership set to `www-data`

> Note: Ansible works identically for both AWS and Azure since the VM runs Ubuntu in both cases.

---

## Step 5 — Verify

```bash
# Site loads
curl -I http://<public_ip>
# Expected: HTTP/1.1 200 OK

# Nginx config on server
ssh ubuntu@<public_ip> 'sudo cat /etc/nginx/sites-available/epicbook'

# App service running
ssh ubuntu@<public_ip> 'sudo systemctl status epicbook'

# Database has data
# AWS:
ssh ubuntu@<public_ip> "mysql -h <rds_endpoint_no_port> -u adminuser -p'<your-db-password>' bookstore -e 'SELECT COUNT(*) FROM Book;'"

# Azure:
ssh ubuntu@<public_ip> "mysql -h <mysql_endpoint> -u adminuser -p'<your-db-password>' bookstore -e 'SELECT COUNT(*) FROM Book;'"
```

Open in browser: `http://<public_ip>` — you should see the EpicBook bookstore with books, gallery, and working cart.

---

## Step 6 — Verify Idempotency

Re-run the playbook without changes:

```bash
ansible-playbook -i inventory.ini site.yml
```

Expected recap:
```
ok=22  changed=0-5  unreachable=0  failed=0  skipped=0
```

- DB schema and seed tasks will show `skipping` — they only run when the database is empty
- `failed=0` is the pass condition

---

## Destroying and Rebuilding

The full project is repeatable. To tear down and rebuild from scratch:

### AWS

```bash
# 1. Destroy all AWS resources
cd terraform/aws/
terraform destroy

# 2. Rebuild
terraform apply

# 3. Update inventory.ini with new public_ip
# 4. Update group_vars/web.yml with new db_host (from rds_endpoint)

# 5. Re-run Ansible — everything is automated including DB seeding
cd ../../ansible/
ansible-playbook -i inventory.ini site.yml
```

### Azure

```bash
# 1. Destroy all Azure resources
cd terraform/azure/
terraform destroy

# 2. Rebuild
terraform apply

# 3. Update inventory.ini with new public_ip
# 4. Update group_vars/web.yml with new db_host (from mysql_endpoint)

# 5. Re-run Ansible — everything is automated including DB seeding
cd ../../ansible/
ansible-playbook -i inventory.ini site.yml
```

---

## Ansible Role Details

### `common`
- Updates apt cache (with 1-hour cache validity for idempotency)
- Installs: `git`, `curl`, `unzip`, `software-properties-common`
- Hardens SSH: disables `PermitRootLogin` and `PasswordAuthentication`
- Handler: `restart ssh` (only fires when sshd_config changes)

### `nginx`
- Installs nginx
- Deploys `epicbook.conf.j2` to `/etc/nginx/sites-available/epicbook`
- Removes default nginx site
- Creates symlink in `sites-enabled`
- Ensures nginx is started and enabled
- Handler: `reload nginx` (fires only when config changes)

**Nginx config strategy:**
- `/assets/*` — served directly from `/var/www/epicbook/public/assets/` with 7-day cache
- All other requests — proxied to Node.js on `127.0.0.1:3000`

### `epicbook`
- Installs: `nodejs`, `npm`, `default-mysql-client`, `python3-pymysql`
- Configures git `safe.directory` for the app path
- Clones `https://github.com/pravinmishraaws/theepicbook` to `/var/www/epicbook`
- Runs `npm install`
- Deploys `config/config.json` from Jinja2 template (Sequelize DB connection)
- **Idempotent DB seeding:**
  - Checks if `Author` table exists → imports schema only if missing
  - Checks if `Book` count is 0 → imports `author_seed.sql` then `books_seed.sql` only if empty
  - Seed order: authors first, then books (foreign key dependency)
- Sets ownership of `/var/www/epicbook` to `www-data:www-data`
- Deploys systemd service unit (`/etc/systemd/system/epicbook.service`)
- Starts and enables `epicbook` service
- Handlers: `restart epicbook`, `reload nginx`

---

## Terraform Variables

### AWS Variables

| Variable | Default | Description |
|---|---|---|
| `aws_region` | `us-east-1` | AWS region |
| `admin_username` | `ubuntu` | EC2 SSH username |
| `private_key_path` | `~/.ssh/id_ed25519` | Path to SSH private key (public key at path + `.pub`) |
| `ami_id` | `ami-0ec10929233384c7f` | Ubuntu 22.04 LTS AMI (us-east-1) |
| `db_password` | `BenefitWallet12345U` | RDS MySQL password |

Override in `terraform/aws/terraform.tfvars`:
```hcl
aws_region       = "us-west-2"
private_key_path = "~/.ssh/my-key"
db_password      = "YourStrongPassword!"
```

### Azure Variables

| Variable | Default | Description |
|---|---|---|
| `resource_group_name` | `epicbook-rg` | Resource group name |
| `location` | `eastus` | Azure region |
| `admin_username` | `ubuntu` | VM SSH username |
| `private_key_path` | `~/.ssh/id_ed25519` | Path to SSH private key |
| `mysql_password` | `BenefitWallet12345U` | Azure MySQL admin password |
| `vm_size` | `Standard_B1s` | Azure VM size (1 vCPU, 1GB RAM) |

Override in `terraform/azure/terraform.tfvars`:
```hcl
location         = "westus"
private_key_path = "~/.ssh/my-key"
mysql_password   = "YourStrongPassword!"
vm_size          = "Standard_B2s"  # 2 vCPU, 4GB RAM
```

---

## Linting

Pre-commit hooks run `yamllint` and `ansible-lint` on all files:

```bash
# Run manually against all files
pre-commit run --all-files

# Or run specific linters
yamllint ansible/
ansible-lint ansible/site.yml
```

---

## Known Issues and Fixes

### 403 Forbidden on first browse
The app is a Node.js/Express application — nginx must proxy to it, not serve static files. Ensure the nginx template uses `proxy_pass http://127.0.0.1:3000` and not `root /var/www/epicbook`.

### "No books available" after deployment
The database is empty on a fresh database instance. The Ansible `epicbook` role handles this automatically — it checks for empty tables and imports `BuyTheBook_Schema.sql`, `author_seed.sql`, and `books_seed.sql` in the correct order. If you need to force a re-seed manually:

```bash
# AWS
HOST="<rds_endpoint_without_port>"
mysql -h $HOST -u adminuser -pYourPassword bookstore < /var/www/epicbook/db/author_seed.sql
mysql -h $HOST -u adminuser -pYourPassword bookstore < /var/www/epicbook/db/books_seed.sql

# Azure
HOST="<mysql_endpoint_without_port>"
mysql -h $HOST -u adminuser -pYourPassword bookstore < /var/www/epicbook/db/author_seed.sql
mysql -h $HOST -u adminuser -pYourPassword bookstore < /var/www/epicbook/db/books_seed.sql
```

### Foreign key error during seed import
Books reference Authors via a foreign key (`AuthorId`). Always import `author_seed.sql` before `books_seed.sql`. The Ansible playbook enforces this order.

### Multi-line mysql commands breaking in terminal
Avoid backslash line continuation (`\`) when pasting mysql commands into a terminal. Use a variable for the hostname and keep each `mysql` invocation on a single line.

### Azure-specific: MySQL connection issues
Azure Database for MySQL Flexible Server requires the client to be on the same VNet or have public access enabled. By default, the server is accessible within the VNet. If you cannot connect:
1. Verify the MySQL server is in the same region as the VM
2. Check that the delegation subnet is correctly configured
3. For external access, enable public access in the MySQL server settings

---

## Security Considerations

This project is configured for a learning/assignment environment. For production use, apply the following hardening:

### AWS

| Risk | Current State | Production Fix |
|---|---|---|
| DB password in plaintext | `group_vars/web.yml` and `terraform.tfvars` | Ansible Vault + `TF_VAR_db_password` env var or AWS Secrets Manager |
| SSH open to `0.0.0.0/0` | Port 22 unrestricted | Restrict to known IPs or use AWS SSM Session Manager |
| RDS publicly accessible | `publicly_accessible = true` | Set to `false`; access only within VPC |
| No HTTPS | HTTP only on port 80 | Add ACM certificate + ALB with HTTPS listener |
| Credentials in git | Possible via `terraform.tfvars` | Add `terraform.tfvars` to `.gitignore`; use secret manager |

### Azure

| Risk | Current State | Production Fix |
|---|---|---|
| DB password in plaintext | `terraform.tfvars` | Use `TF_VAR_mysql_password` env var or Azure Key Vault |
| SSH open to `0.0.0.0/0` | NSG allows all sources | Restrict NSG to known IPs or use Azure Bastion |
| MySQL publicly accessible | Default in VNet | Use private endpoint; disable public access |
| No HTTPS | HTTP only on port 80 | Add Azure Front Door + SSL certificate |
| Credentials in git | Possible via `terraform.tfvars` | Add `terraform.tfvars` to `.gitignore`; use Key Vault |

---

## Quick Reference: Cloud Commands

### AWS

```bash
# Terraform
cd terraform/aws/
terraform init
terraform plan
terraform apply
terraform output
terraform destroy

# Get outputs
terraform output public_ip
terraform output rds_endpoint
```

### Azure

```bash
# Terraform
cd terraform/azure/
terraform init
terraform plan
terraform apply
terraform output
terraform destroy

# Get outputs
terraform output public_ip
terraform output mysql_fqdn
terraform output mysql_endpoint

# Azure CLI helpers
az vm show -d -g epicbook-rg -n epicbook-vm --query publicIps
az mysql flexible-server show -g epicbook-rg -n epicbook-mysql --query fullyQualifiedDomainName
```

---

## License

MIT
