# EpicBook on Azure — Ansible Roles Deployment

Configuration management for deploying the [EpicBook](https://github.com/pravinmishraaws/theepicbook) Node.js/Express bookstore application onto a Microsoft Azure virtual machine using **Ansible roles**.

> **Project context:** Built during the Cloud DevOps Bootcamp (The CloudAdvisory Oy, 2026) as the configuration half of a two-repository deployment. The companion repository [infra-epicbook](https://github.com/dowusubekoe-dev/infra-epicbook) provisions the Azure infrastructure with Terraform; this repository configures the server and deploys the application with Ansible. This repo contains no Terraform — infrastructure lives in infra-epicbook.

## What this repo does

A single playbook (`site.yml`) applies three roles in order against the `web` host group:

| Role | Responsibility |
| --- | --- |
| `common` | Base system preparation and package updates |
| `nginx` | Installs and configures Nginx as the reverse proxy (site config and service unit rendered from Jinja2 templates) |
| `epicbook` | Deploys the EpicBook application, renders its `config.json` from a template, and registers it as a systemd service |

**Request flow:** Browser → Nginx (port 80) → EpicBook Node.js service (port 3000) → Azure MySQL Flexible Server (provisioned by infra-epicbook, reachable only over the virtual network).

## Repository structure

```
├── site.yml                  # Playbook: common → nginx → epicbook
├── ansible.cfg               # Ansible settings (pipelining, timeouts)
├── ansible-pipelines.yml     # Azure DevOps pipeline for this repo
├── group_vars/
│   ├── web/web.yml           # Variables for the web host group
│   ├── web.yml.example       # Sample variable file
│   └── web.yml.azure-example # Sample variable file (Azure variant)
└── roles/
    ├── common/               # tasks + handlers
    ├── nginx/                # tasks, handlers, templates (site config, service)
    └── epicbook/             # tasks, handlers, templates (config.json, systemd unit)
```

## How the deployment runs

1. **Infrastructure first:** infra-epicbook's Terraform pipeline provisions the Azure resource group, virtual network, VM, and MySQL Flexible Server, and publishes its outputs (including the VM address) as a pipeline artifact (`infra-outputs`).
2. **This repo's pipeline** (`ansible-pipelines.yml`, Azure DevOps, self-hosted agent pool) is triggered by the infra pipeline, downloads the `infra-outputs` artifact to build its inventory, and runs the playbook. Secrets are supplied through an Azure DevOps variable group, not committed to the repo.
3. **Manually:** point an inventory at the VM and run `ansible-playbook -i <inventory> site.yml`. Use the `.example` variable files as the template for your own `group_vars` values.

## Skills demonstrated

Ansible roles and handlers, Jinja2 templating, systemd service management, Nginx reverse proxy configuration, Azure DevOps YAML pipelines with cross-pipeline artifact consumption, and separation of infrastructure (Terraform) from configuration (Ansible) across repositories.
