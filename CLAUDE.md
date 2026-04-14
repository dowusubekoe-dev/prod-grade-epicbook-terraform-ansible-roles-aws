# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Production-grade EpicBook Node.js/Express bookstore deployment on AWS using Terraform for infrastructure and Ansible roles for configuration management. Covers Terraform AWS provisioning, Ansible role structure (tasks, templates, handlers, group_vars), idempotency, DB seeding, and systemd service management.

## Commands

### Terraform
```bash
cd terraform/aws/
terraform init              # Initialize
terraform plan              # Preview changes
terraform apply             # Provision infrastructure (EC2 + RDS — takes ~10 min)
terraform output            # Show public_ip, admin_user, rds_endpoint
terraform destroy           # Clean up all resources
```

### After `terraform apply` — update two files before running Ansible
```bash
# 1. Update ansible/inventory.ini with new EC2 public IP
# 2. Update ansible/group_vars/web.yml with new RDS endpoint (strip :3306 for db_host)
```

### Ansible
```bash
cd ansible/
ansible-playbook -i inventory.ini site.yml              # Run all roles
ansible-playbook -i inventory.ini site.yml --check      # Dry run
ansible-playbook -i inventory.ini site.yml --diff       # Show config changes
```

### Linting
```bash
pre-commit run --all-files  # Run yamllint and ansible-lint
```

## Architecture

**Infrastructure (Terraform — AWS):**
- VPC (`10.0.0.0/16`) with DNS support, two public subnets across two AZs
- Internet Gateway + Route Table (public subnet → IGW)
- EC2 Security Group: inbound SSH (22) and HTTP (80)
- RDS Security Group: inbound MySQL (3306) from EC2 security group only
- EC2: `t3.micro`, Ubuntu 22.04, subnet 1, SSH key auth, public IP
- RDS: MySQL 8.0, `db.t3.micro`, 20GB, DB subnet group across both subnets
- Key pair created from `var.private_key_path` + `.pub`

**Request flow:**
```
Browser → nginx (port 80) → epicbook systemd service (port 3000) → RDS MySQL
                ↓
         /assets/* served directly from /var/www/epicbook/public/assets/
```

**Configuration (Ansible):**
```
Role Execution Order: common → nginx → epicbook

common   → apt update, baseline packages (git, curl, unzip), SSH hardening
nginx    → Install nginx, deploy reverse proxy template, enable site, start service
epicbook → Install Node.js/npm, clone repo, npm install, deploy DB config,
           import schema + seed data (idempotent), set ownership, run as systemd service
```

**File Structure:**
```
prod-grade-epicbook-terraform-ansible-roles-aws/
├── terraform/aws/
│   ├── main.tf               # VPC, subnets, IGW, SGs, EC2, RDS, key pair
│   ├── variables.tf          # aws_region, admin_username, private_key_path, ami_id, db_password
│   ├── output.tf             # public_ip, admin_user, ssh_access_command, rds_endpoint
│   └── terraform.tfvars      # Variable overrides
├── ansible/
│   ├── inventory.ini         # EC2 public IP + SSH key config (update after terraform apply)
│   ├── site.yml              # Three plays: common, nginx, epicbook
│   ├── group_vars/
│   │   └── web.yml           # app_repo, app_dest, app_user, db_host, db_name, db_user, db_pass
│   ├── ansible.cfg           # Pipelining, timeouts, stdout_callback=yaml
│   └── roles/
│       ├── common/
│       │   ├── tasks/main.yml    # apt update, packages, SSH hardening
│       │   └── handlers/main.yml # restart ssh
│       ├── nginx/
│       │   ├── tasks/main.yml    # Install nginx, deploy config, enable site
│       │   ├── templates/
│       │   │   └── epicbook.conf.j2  # Reverse proxy + /assets/ static block
│       │   └── handlers/main.yml # reload nginx
│       └── epicbook/
│           ├── tasks/main.yml    # Node.js, npm install, DB seed, systemd service
│           ├── templates/
│           │   ├── config.json.j2       # Sequelize DB connection config
│           │   └── epicbook.service.j2  # systemd unit (runs node server.js as www-data)
│           └── handlers/main.yml # restart epicbook, reload nginx
├── .pre-commit-config.yaml   # Linting hooks (yamllint, ansible-lint)
├── .editorconfig
└── .venv/                    # Python virtual environment (gitignored)
```

## Key Implementation Details

**nginx template (epicbook.conf.j2):**
- `/assets/` location: served directly from `/var/www/epicbook/public/assets/` with `alias`
- `/` location: reverse proxy to `http://127.0.0.1:3000` (Node.js app)
- This is a Node.js/Express app — NOT a static site. Do not use `root`/`try_files` for the main location.

**epicbook role — what it does:**
- Installs `nodejs`, `npm`, `default-mysql-client`, `python3-pymysql`
- Clones `https://github.com/pravinmishraaws/theepicbook` to `/var/www/epicbook` (`force: yes`)
- Runs `npm install` for Express, Sequelize, mysql2 dependencies
- Deploys `config/config.json` (Sequelize DB config) from Jinja2 template using `db_host`, `db_user`, `db_pass`, `db_name`
- **Idempotent DB seeding (order matters due to FK constraints):**
  1. Check if `Author` table exists → import `BuyTheBook_Schema.sql` only if missing
  2. Check if `Book` count == 0 → import `author_seed.sql` then `books_seed.sql` only if empty
  3. Authors must be seeded before books (`Book.AuthorId` FK references `Author.id`)
- Sets ownership of `/var/www/epicbook` to `www-data:www-data` recursively
- Deploys and starts `epicbook.service` systemd unit (runs `node server.js` as `www-data` on port 3000)

**group_vars/web.yml — variables used across roles:**
- `app_repo`, `app_dest`, `app_user`, `app_group` — repo and filesystem config
- `db_host` — RDS hostname WITHOUT port (strip `:3306` from rds_endpoint output)
- `db_port`, `db_name`, `db_user`, `db_pass`, `db_dialect` — database connection

**Idempotency:**
- DB schema import: skips if `Author` table already exists
- DB seed import: skips if `Book` count > 0
- Handlers fire only when config/service files change
- `changed_when: false` on read-only shell checks (table exists, book count)

**SSH Authentication:**
- Passwordless SSH required
- Test: `ssh ubuntu@<public_ip> 'hostname'`

## Verification Checklist

- [ ] VM reachable via SSH key (`ssh ubuntu@<public_ip> 'hostname'`)
- [ ] Ports 22 and 80 open (Security Group)
- [ ] EpicBook accessible at `http://<public_ip>` (books visible, cart works)
- [ ] Nginx config at `/etc/nginx/sites-available/epicbook`
- [ ] `sudo systemctl status epicbook` → active (running)
- [ ] `sudo journalctl -u epicbook -n 20` → SQL queries executing against RDS
- [ ] Playbook re-run shows `failed=0`, DB seed tasks show `skipping`
