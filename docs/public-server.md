# Public Server

This document describes the configuration of LIDSOL's public-facing server (`lidsol.fi-b.unam.mx`). It is managed with Ansible and includes four roles: **security**, **network**, **nginx**, and **router**. The mirrors role is covered separately in [mirrors.md](mirrors.md).

## Table of Contents

- [Overview](#overview)
- [Inventory](#inventory)
- [Running the Playbook](#running-the-playbook)
- [Roles](#roles)
  - [Security](#security)
  - [Network](#network)
  - [Nginx](#nginx)
  - [Router](#router)
- [Network Diagram](#network-diagram)
- [Firewall (nftables)](#firewall-nftables)
- [VPN (WireGuard)](#vpn-wireguard)
- [DNS / DHCP (DNSmasq)](#dns--dhcp-dnsmasq)
- [Troubleshooting](#troubleshooting)

## Overview

The public server acts as the perimeter router and mirrors host for LIDSOL. It bridges the university's public network (`132.248.59.0/24`) to the internal lab LAN (`10.8.24.0/24`) and exposes services on `lidsol.fi-b.unam.mx`.

| Host group | Description |
|------------|-------------|
| `servers` | The main public server; runs mirrors, nginx, security hardening |
| `routers` | The gateway/router; runs routing, firewall, VPN, DNSmasq |

## Inventory

File: `public-server/inventory.yml`

Edit this file to set the correct `ansible_host` (IP address) and `ansible_user` for each host.

## Running the Playbook

```bash
# Full run (all roles on all hosts)
ansible-playbook -i public-server/inventory.yml public-server/main.yaml

# Dry run (no changes applied)
ansible-playbook -i public-server/inventory.yml public-server/main.yaml --check

# Limit to a single host group
ansible-playbook -i public-server/inventory.yml public-server/main.yaml --limit servers

# Limit to a single role/tag
ansible-playbook -i public-server/inventory.yml public-server/main.yaml --tags nginx
```

## Roles

### Security

**Path**: `public-server/security/`

Applied to all hosts. Hardens the server by:

1. **SSH hardening** (`tasks/sshd.yml`):
   - Disables password authentication (public-key only).
   - Disables root login over SSH.
   - Restarts `sshd` via a handler only when the configuration changes.

2. **Unattended upgrades** (`tasks/unattended-upgrades.yml`):
   - Installs `unattended-upgrades` and enables automatic security updates.
   - Ensures that critical OS patches are applied without operator intervention.

> **Important**: Before applying this role to a new server, ensure your SSH public key is present in `~/.ssh/authorized_keys` on the target host. Once password auth is disabled, key-based access is the only way in.

### Network

**Path**: `public-server/network/`

Optimizes the network stack for high-throughput workloads (e.g., mirror syncing).

1. **IRQ balancing** (`tasks/irqbalance.yaml`):
   - Installs and enables `irqbalance` to distribute hardware interrupts across CPU cores.

2. **Kernel tuning** (`tasks/sysctl.yaml`):
   - Sets `net.core` and `net.ipv4` kernel parameters for improved TCP performance.
   - Parameters are persisted in `/etc/sysctl.d/`.

3. **Interface configuration** (`tasks/interfaces.yaml`):
   - Configures network interfaces as needed.

### Nginx

**Path**: `public-server/nginx/`

Sets up the Nginx web server and reverse proxy for public-facing services.

- Installs Nginx.
- Configures virtual hosts for `lidsol.fi-b.unam.mx`.
- Obtains and renews TLS certificates via **Certbot** (Let's Encrypt).
- Serves as the front end for the Linux distribution mirrors (see [mirrors.md](mirrors.md)).

**Useful commands on the server**:

```bash
sudo systemctl status nginx
sudo nginx -t                  # Test configuration syntax
sudo certbot renew --dry-run   # Test certificate renewal
```

### Router

**Path**: `public-server/router/`

Configures the gateway node to route traffic between the public internet and the internal LAN.

| Task file | Purpose |
|-----------|---------|
| `tasks/main.yaml` | Orchestrates all router sub-tasks |
| `files/armbian.yaml` | Netplan network configuration (WAN + LAN bridge) |
| `files/lan.conf` | DNSmasq LAN DNS/DHCP configuration |
| `files/nftables.conf` | Main nftables firewall rules |
| `files/nftables-override.conf` | Additional nftables rules (overrides) |
| `files/99-router.conf` | Router-specific sysctl tuning |
| `files/wg0.conf` | WireGuard VPN tunnel configuration |

Sub-tasks performed:

- **Netplan**: Applies the `armbian.yaml` network configuration file and runs `netplan apply`.
- **DNSmasq**: Deploys `lan.conf` to provide DHCP and local DNS resolution on the LAN.
- **nftables**: Deploys firewall rules and enables the `nftables` service.
- **WireGuard**: Deploys `wg0.conf` and enables the `wg-quick@wg0` service.

## Network Diagram

```
Internet (132.248.59.0/24)
        │
        │  WAN: 132.248.59.72/24
        │  GW:  132.248.59.254
        ▼
┌───────────────────────────────┐
│         Router / Gateway      │
│    nftables (NAT + stateful)  │
│    DNSmasq (DHCP/DNS)         │
│    WireGuard (VPN, wg0)       │
└──────────────┬────────────────┘
               │ LAN bridge br0
               │ 10.8.24.0/24
               ▼
       ┌───────────────────┐
       │  Internal LAN     │
       │  K3s cluster      │
       │  (10.8.24.x)      │
       └───────────────────┘
```

## Firewall (nftables)

Rules are defined in `public-server/router/files/nftables.conf`. The firewall implements:

- **Stateful packet filtering**: Established/related connections are automatically allowed.
- **NAT masquerade**: Internal LAN traffic is masqueraded to the WAN IP when going out to the internet.
- **Port forwarding**: Specific ports can be forwarded from the WAN to internal hosts.
- **Default drop policy**: Any traffic not explicitly allowed is dropped.

To inspect active rules on the router:

```bash
sudo nft list ruleset
```

To reload rules after a change (applied by Ansible via the `nftables` handler):

```bash
sudo systemctl reload nftables
```

## VPN (WireGuard)

WireGuard is used to establish secure tunnels between the lab's infrastructure and remote peers. The configuration is stored in `public-server/router/files/wg0.conf`.

> **Note**: `wg0.conf` contains private keys. This file must **never** be committed to the repository with real key material. Use Ansible Vault to encrypt sensitive values, or manage the file out-of-band.

**WireGuard management commands**:

```bash
sudo wg show                    # Show current VPN status and peers
sudo wg-quick up wg0            # Bring the tunnel up manually
sudo wg-quick down wg0          # Bring the tunnel down
sudo systemctl status wg-quick@wg0
```

## DNS / DHCP (DNSmasq)

DNSmasq provides DHCP leases and local DNS resolution for the `10.8.24.0/24` LAN. Configuration: `public-server/router/files/lan.conf`.

Key settings:

- **DHCP range**: Defined in `lan.conf` (check the file for the exact range).
- **DNS forwarding**: Upstream DNS servers are configured for external name resolution.
- **Static leases**: Cluster nodes (hp-alpha, hp-beta, gamma) have static DHCP leases tied to their MAC addresses.

To check DNSmasq status on the router:

```bash
sudo systemctl status dnsmasq
sudo journalctl -u dnsmasq -f
```

## Troubleshooting

**Cannot connect via SSH after running security role**:
- Verify your public key was in `authorized_keys` before the playbook ran.
- Try connecting from the console (KVM/IPMI) to recover access.

**Nginx returns 502 Bad Gateway**:
```bash
sudo nginx -t                     # Check config syntax
sudo systemctl status nginx
sudo journalctl -u nginx -f
```

**WireGuard tunnel not coming up**:
```bash
sudo journalctl -u wg-quick@wg0 -f
sudo wg show                       # Check handshake timestamps
```

**nftables rules not applied after reboot**:
```bash
sudo systemctl enable nftables
sudo systemctl start nftables
sudo nft list ruleset
```

**Netplan configuration errors**:
```bash
sudo netplan try     # Apply with 120-second rollback safety
sudo netplan apply   # Apply permanently
```
