# EpicBook — Production Deployment on AWS

A production-grade deployment of the [EpicBook](https://github.com/pravinmishraaws/theepicbook) Node.js/Express bookstore application using **Terraform** for AWS infrastructure provisioning and **Ansible roles** for configuration management.

---

## Architecture

```
                        ┌─────────────────────────────────────────┐
                        │           AWS us-east-1                 │
                        │                                         │
                        │  ┌──────────────────────────────────┐   │
                        │  │     VPC  10.0.0.0/16             │   │
                        │  │                                  │   │
                        │  │  ┌────────────┐ ┌─────────────┐  │   │
                        │  │  │ Subnet 1   │ │  Subnet 2   │  │   │
                        │  │  │ 10.0.1.0/24│ │ 10.0.2.0/24 │  │   │
                        │  │  │            │ │             │  │   │
                        │  │  │ ┌────────┐ │ │ ┌─────────┐ │  │   │
                        │  │  │ │  EC2   │ │ │ │   RDS   │ │  │   │
                        │  │  │ │t3.micro│ │ │ │ MySQL8  │ │  │   │
                        │  │  │ │Ubuntu  │ │ │ │db.t3.mic│ │  │   │
                        │  │  │ └────────┘ │ │ └─────────┘ │  │   │
                        │  │  └────────────┘ └─────────────┘  │   │
                        │  │         │              │         │   │
                        │  │    SG: 22,80      SG: 3306       │   │
                        │  │    (public)     (from EC2 only)  │   │
                        │  │                                  │   │
                        │  │         Internet Gateway         │   │
                        │  └──────────────────────────────────┘   │
                        └─────────────────────────────────────────┘
                                        │
                               Browser → port 80
                               SSH    → port 22
```

**Request flow:**
```
Browser → nginx (port 80) → Node.js / epicbook service (port 3000) → RDS MySQL
                ↓
         /assets/* served directly from disk
```

---

## Project Structure

```
epicbook-prod/
├── terraform/
│   └── aws/
│       ├── main.tf              # VPC, subnets, IGW, SGs, EC2, RDS
│       ├── variables.tf         # Input variables (region, AMI, key path, DB password)
│       ├── output.tf            # Outputs: public_ip, admin_user, rds_endpoint
│       └── terraform.tfvars     # Variable overrides (not committed with secrets)
├── ansible/
│   ├── inventory.ini            # EC2 public IP + SSH config (update after apply)
│   ├── site.yml                 # Playbook: common → nginx → epicbook
│   ├── ansible.cfg              # Ansible settings (pipelining, timeouts, etc.)
│   ├── group_vars/
│   │   └── web.yml              # Shared variables: repo, paths, DB credentials
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
| AWS CLI | >= 2.x | Authentication |
| SSH key pair | ed25519 | VM access |

**AWS CLI authenticated:**
```bash
aws sts get-caller-identity   # should return your account ID
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

---

## Step 2 — Update Ansible with Infrastructure Values

After `terraform apply`, update two files with the output values:

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

---

## Step 3 — Test SSH Access

```bash
ssh ubuntu@<public_ip> 'hostname'
```

Expected output: the EC2 private hostname (e.g. `ip-10-0-1-145`). If this works, Ansible can connect.

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
7. Sequelize `config/config.json` deployed with RDS connection details
8. Database schema created on RDS (only on first run — idempotent check)
9. Author and book seed data imported (only if empty — idempotent check)
10. `epicbook` systemd service created, started, and enabled
11. File ownership set to `www-data`

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
ssh ubuntu@<public_ip> "mysql -h <rds_endpoint_no_port> -u adminuser -p'<your-db-password>' bookstore -e 'SELECT COUNT(*) FROM Book;'"
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

| Variable | Default | Description |
|---|---|---|
| `aws_region` | `us-east-1` | AWS region |
| `admin_username` | `ubuntu` | EC2 SSH username |
| `private_key_path` | `~/.ssh/id_ed25519` | Path to SSH private key (public key at path + `.pub`) |
| `ami_id` | `ami-0ec10929233384c7f` | Ubuntu 22.04 LTS AMI (us-east-1) |
| `db_password` | `BenefitWallet12345U` | RDS MySQL password |

Override any variable in `terraform/aws/terraform.tfvars`:
```hcl
aws_region       = "us-west-2"
private_key_path = "~/.ssh/my-key"
db_password      = "YourStrongPassword!"
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
The database is empty on a fresh RDS instance. The Ansible `epicbook` role handles this automatically — it checks for empty tables and imports `BuyTheBook_Schema.sql`, `author_seed.sql`, and `books_seed.sql` in the correct order. If you need to force a re-seed manually:

```bash
HOST="<rds_endpoint_without_port>"
mysql -h $HOST -u adminuser -pYourPassword bookstore < /var/www/epicbook/db/author_seed.sql
mysql -h $HOST -u adminuser -pYourPassword bookstore < /var/www/epicbook/db/books_seed.sql
```

### Foreign key error during seed import
Books reference Authors via a foreign key (`AuthorId`). Always import `author_seed.sql` before `books_seed.sql`. The Ansible playbook enforces this order.

### Multi-line mysql commands breaking in terminal
Avoid backslash line continuation (`\`) when pasting mysql commands into a terminal. Use a variable for the hostname and keep each `mysql` invocation on a single line.

---

## Security Considerations

This project is configured for a learning/assignment environment. For production use, apply the following hardening:

| Risk | Current State | Production Fix |
|---|---|---|
| DB password in plaintext | `group_vars/web.yml` and `terraform.tfvars` | Ansible Vault + `TF_VAR_db_password` env var or AWS Secrets Manager |
| SSH open to `0.0.0.0/0` | Port 22 unrestricted | Restrict to known IPs or use AWS SSM Session Manager |
| RDS publicly accessible | `publicly_accessible = true` | Set to `false`; access only within VPC |
| No HTTPS | HTTP only on port 80 | Add ACM certificate + ALB with HTTPS listener |
| Credentials in git | Possible via `terraform.tfvars` | Add `terraform.tfvars` to `.gitignore`; use secret manager |

---

## License

MIT
