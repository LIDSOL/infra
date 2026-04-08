# LIDSOL Infrastructure

[![License](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](LICENSE)

Infrastructure-as-code repository for [LIDSOL](https://lidsol.unam.mx) (Laboratorio de Investigación y Desarrollo de Software Libre) at UNAM. This repository manages the full stack: a production Kubernetes cluster, public-facing services, Linux distribution mirrors, and the underlying network.

## Table of Contents

- [Architecture Overview](#architecture-overview)
- [Repository Structure](#repository-structure)
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Components](#components)
- [Contributing](#contributing)
- [License](#license)

## Architecture Overview

```
Internet
    │
    ▼
┌─────────────────────────────────────────────────────────────────────┐
│  Router / Gateway (Armbian)                                         │
│  WAN: 132.248.59.72/24  ──►  LAN: 10.8.24.0/24                     │
│  nftables firewall, DNSmasq, WireGuard VPN                         │
└──────────────────────────────┬──────────────────────────────────────┘
                               │ LAN
            ┌──────────────────┼──────────────────┐
            ▼                  ▼                  ▼
      ┌──────────┐       ┌──────────┐       ┌──────────┐
      │ hp-alpha │       │ hp-beta  │       │  gamma   │
      │K3s master│       │K3s agent │       │K3s agent │
      └──────────┘       └──────────┘       └──────────┘
            │                  │                  │
            └──────────────────┼──────────────────┘
                               │
                    ┌──────────▼──────────┐
                    │  Kubernetes (K3s)   │
                    │  API: 10.8.24.101   │
                    │  MetalLB: .102-.120 │
                    │                     │
                    │  ArgoCD (GitOps)    │
                    │  Cert-Manager       │
                    │  Ingress-Nginx      │
                    │  Longhorn (storage) │
                    │  LIDSOL Website     │
                    │  Nextcloud          │
                    │  DrawDB             │
                    │  Speedtest Tracker  │
                    └─────────────────────┘

Public Server (lidsol.fi-b.unam.mx)
  Nginx + Let's Encrypt
  Linux Mirrors: AlmaLinux, ArchLinux, Debian, Fedora, Linux Mint
```

## Repository Structure

```
infra/
├── README.md                  # This file
├── CONTRIBUTING.md            # How to contribute
├── LICENSE                    # Apache 2.0 License
├── docs/                      # Detailed documentation
│   ├── cluster.md             # K3s cluster setup and management
│   ├── gitops.md              # GitOps / ArgoCD deployments
│   ├── public-server.md       # Public server (mirrors, router, security)
│   └── mirrors.md             # Linux distribution mirrors
├── cluster/                   # Kubernetes cluster provisioning
│   ├── argo-config/           # ArgoCD application manifests
│   ├── config/                # Ansible inventory and variables
│   ├── k3s-ansible/           # Git submodule: k3s-ansible
│   ├── node.yml               # Ansible playbook: node preparation
│   └── argocd.yml             # Ansible playbook: ArgoCD + Longhorn install
├── gitops/                    # Kubernetes manifests (managed by ArgoCD)
│   ├── certmanager-deployment.yaml
│   ├── ingress-deployment.yaml
│   ├── longhorn-ui-deployment.yaml
│   ├── nextcloud-deployment.yaml
│   ├── website-deployment.yaml
│   ├── https-issuer-deployment.yaml
│   ├── drawdb-deployment.yaml
│   ├── speedtest-tracker-deployment.yaml
│   └── ExplicacionIngress.md  # Ingress controller documentation (Spanish)
└── public-server/             # Public server configuration
    ├── main.yaml              # Main Ansible playbook
    ├── inventory.yml          # Ansible inventory
    ├── security/              # Role: SSH hardening + automatic updates
    ├── network/               # Role: IRQ balancing + sysctl tuning
    ├── nginx/                 # Role: Nginx + Let's Encrypt
    ├── router/                # Role: routing, firewall, VPN, DNS
    └── mirrors/               # Role: Linux distribution mirrors
```

## Prerequisites

The following tools must be installed on your workstation before working with this repository.

| Tool | Minimum Version | Purpose |
|------|----------------|---------|
| [Ansible](https://docs.ansible.com/ansible/latest/installation_guide/) | 2.14 | Configuration management and playbook execution |
| [kubectl](https://kubernetes.io/docs/tasks/tools/) | 1.28 | Kubernetes cluster management |
| [Git](https://git-scm.com/) | 2.40 | Version control and submodule support |
| Python | 3.10 | Required by Ansible |

> **Note**: Access to the cluster nodes via SSH (with your key in `cluster/config/authorized_keys`) is required for cluster operations.

## Quick Start

### 1. Clone the repository

```bash
git clone --recurse-submodules https://github.com/LIDSOL/infra.git
cd infra
```

If you already cloned without `--recurse-submodules`:

```bash
git submodule update --init --recursive
```

### 2. Set up the Kubernetes cluster

See [docs/cluster.md](docs/cluster.md) for full details.

```bash
# 1. Configure node variables
cp cluster/config/host_vars/hp-alpha.yml cluster/config/host_vars/<your-node>.yml
# Edit the file with your node's IP and network settings

# 2. Prepare the nodes
ansible-playbook -i cluster/config/hosts.ini cluster/node.yml

# 3. Deploy K3s
ansible-playbook -i cluster/config/hosts.ini cluster/k3s-ansible/site.yml

# 4. Install ArgoCD and Longhorn
ansible-playbook -i cluster/config/hosts.ini cluster/argocd.yml
```

### 3. Configure the public server

See [docs/public-server.md](docs/public-server.md) for full details.

```bash
# Review and update the inventory
vim public-server/inventory.yml

# Run the main playbook
ansible-playbook -i public-server/inventory.yml public-server/main.yaml
```

### 4. Deploy applications via GitOps

Once ArgoCD is running, it automatically syncs manifests from the `gitops/` directory. See [docs/gitops.md](docs/gitops.md) for details.

## Components

| Component | Documentation | Description |
|-----------|--------------|-------------|
| K3s Cluster | [docs/cluster.md](docs/cluster.md) | Lightweight Kubernetes cluster on bare metal |
| GitOps | [docs/gitops.md](docs/gitops.md) | ArgoCD-managed application deployments |
| Public Server | [docs/public-server.md](docs/public-server.md) | Nginx, routing, security, and mirrors |
| Mirrors | [docs/mirrors.md](docs/mirrors.md) | Linux distribution mirror setup and sync |

## Contributing

We welcome contributions of all kinds — bug fixes, documentation improvements, new features, and feedback.

Please read [CONTRIBUTING.md](CONTRIBUTING.md) before submitting a pull request.

## License

This project is licensed under the [Apache License 2.0](LICENSE).
