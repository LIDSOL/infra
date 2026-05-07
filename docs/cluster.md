# K3s Cluster

This document covers how to provision, configure, and manage the LIDSOL Kubernetes cluster, which is built on [K3s](https://k3s.io/) and deployed using Ansible.

## Table of Contents

- [Architecture](#architecture)
- [Node Inventory](#node-inventory)
- [Network Configuration](#network-configuration)
- [Prerequisites](#prerequisites)
- [Cluster Setup](#cluster-setup)
  - [1. Prepare the Nodes](#1-prepare-the-nodes)
  - [2. Deploy K3s](#2-deploy-k3s)
  - [3. Install ArgoCD and Longhorn](#3-install-argocd-and-longhorn)
- [Accessing the Cluster](#accessing-the-cluster)
- [Upgrading K3s](#upgrading-k3s)
- [Storage (Longhorn)](#storage-longhorn)
- [Load Balancing (MetalLB)](#load-balancing-metallb)
- [High Availability (Kube-vip)](#high-availability-kube-vip)
- [Troubleshooting](#troubleshooting)

## Architecture

The cluster consists of three bare-metal nodes connected through the internal LAN (`10.8.24.0/24`). A virtual IP (`10.8.24.101`) is provided by Kube-vip for high-availability access to the Kubernetes API server.

```
LAN: 10.8.24.0/24
                    ┌──────────────────────────────┐
                    │  Virtual IP: 10.8.24.101      │
                    │  (Kube-vip, ARP mode)          │
                    └──────────────┬───────────────┘
                                   │
              ┌────────────────────┼────────────────────┐
              ▼                    ▼                    ▼
        ┌──────────┐         ┌──────────┐         ┌──────────┐
        │ hp-alpha │         │ hp-beta  │         │  gamma   │
        │  master  │         │  agent   │         │  agent   │
        └──────────┘         └──────────┘         └──────────┘

MetalLB pool: 10.8.24.102 – 10.8.24.120  (LoadBalancer services)
ArgoCD:       10.8.24.102
Longhorn UI:  10.8.24.105
```

**Key components installed by `argocd.yml`**:

| Component | Version | Purpose |
|-----------|---------|---------|
| K3s | v1.30.2+k3s2 | Lightweight Kubernetes distribution |
| ArgoCD | Latest stable | GitOps continuous delivery |
| Longhorn | v1.8.1 | Distributed block storage |
| ArgoCD Image Updater | Latest | Automatic container image updates |
| MetalLB | v0.14.8 | Bare-metal load balancer |
| Kube-vip | v0.8.2 | HA virtual IP for the API server |

## Node Inventory

Inventory file: `cluster/config/hosts.ini`

| Hostname | Role | Internal IP | Config File |
|----------|------|------------|-------------|
| `hp-alpha` | master | 10.8.24.x | `cluster/config/host_vars/hp-alpha.yml` |
| `hp-beta` | agent | 10.8.24.x | `cluster/config/host_vars/hp-beta.yml` |
| `gamma` | agent | 10.8.24.x | `cluster/config/host_vars/gamma.yml` |

Node-specific variables (network interface, IP, etc.) are stored in `cluster/config/host_vars/<hostname>.yml`.

## Network Configuration

Cluster-wide network settings live in `cluster/config/group_vars/all.yml`:

| Variable | Default | Description |
|----------|---------|-------------|
| `k3s_version` | `v1.30.2+k3s2` | K3s release to install |
| `k3s_token` | (set by operator) | Shared cluster token — **keep secret** |
| `api_endpoint` | `10.8.24.101` | Kube-vip virtual IP |
| `kube_vip_tag_version` | `v0.8.2` | Kube-vip image version |
| `metal_lb_speaker_tag_version` | `v0.14.8` | MetalLB version |
| `metal_lb_ip_range` | `10.8.24.102-10.8.24.120` | Pool for LoadBalancer IPs |
| `flannel_iface` | node-specific | Network interface for Flannel CNI |
| `cluster_cidr` | `10.42.0.0/16` | Pod CIDR |
| `service_cidr` | `10.43.0.0/16` | Service CIDR |

**CNI options**: Flannel (default), Calico, or Cilium — controlled by variables in `all.yml`.

## Prerequisites

- SSH access to all cluster nodes with a key listed in `cluster/config/authorized_keys`.
- The user running the playbooks must have passwordless `sudo` on the nodes (or supply the sudo password via `--ask-become-pass`).
- Ansible ≥ 2.14 installed on the control machine.
- The k3s-ansible submodule must be initialized:
  ```bash
  git submodule update --init --recursive
  ```

## Cluster Setup

### 1. Prepare the Nodes

The `node.yml` playbook configures each node before K3s is deployed. It:

- Creates a dedicated sudo user.
- Installs authorized SSH keys.
- Enables unattended security updates.
- Installs NFS and iSCSI client packages (for external storage).
- Configures the network interface used for the cluster.

```bash
ansible-playbook -i cluster/config/hosts.ini cluster/node.yml
```

> You may be prompted for the SSH password on the first run if key-based auth is not yet set up. Pass `--ask-pass` if needed.

### 2. Deploy K3s

The `k3s-ansible` submodule provides the deployment playbook.

```bash
ansible-playbook -i cluster/config/hosts.ini cluster/k3s-ansible/site.yml
```

After this step, K3s is running. Retrieve the kubeconfig:

```bash
scp <master-node>:/etc/rancher/k3s/k3s.yaml ~/.kube/config
# Replace the server IP 127.0.0.1 with the VIP:
sed -i 's/127.0.0.1/10.8.24.101/' ~/.kube/config
kubectl get nodes
```

### 3. Install ArgoCD and Longhorn

The `argocd.yml` playbook installs ArgoCD, Longhorn, and the ArgoCD Image Updater on top of the running cluster.

```bash
ansible-playbook -i cluster/config/hosts.ini cluster/argocd.yml
```

After completion:

- **ArgoCD** is accessible at `http://10.8.24.102` (LoadBalancer IP).
- The initial admin password is stored in the `argocd-initial-admin-secret` Kubernetes secret:
  ```bash
  kubectl -n argocd get secret argocd-initial-admin-secret \
    -o jsonpath="{.data.password}" | base64 -d
  ```
- ArgoCD is configured (via `cluster/argo-config/default-manifest.yml`) to watch the `gitops/` directory of this repository and auto-sync all manifests.

## Accessing the Cluster

```bash
# List nodes
kubectl get nodes -o wide

# List all pods
kubectl get pods -A

# Access ArgoCD UI (port-forward if LoadBalancer IP is not reachable)
kubectl port-forward svc/argocd-server -n argocd 8080:443
# Then open https://localhost:8080
```

## Upgrading K3s

To upgrade K3s, update the `k3s_version` variable in `cluster/config/group_vars/all.yml` and re-run the K3s playbook:

```bash
ansible-playbook -i cluster/config/hosts.ini cluster/k3s-ansible/site.yml
```

Always check the [K3s release notes](https://github.com/k3s-io/k3s/releases) for breaking changes before upgrading.

## Storage (Longhorn)

[Longhorn](https://longhorn.io/) provides distributed replicated block storage across the cluster nodes.

- **Version**: v1.8.1
- **UI**: Available at `http://10.8.24.105` (LoadBalancer service `longhorn-ui` in namespace `longhorn-system`).
- **Default StorageClass**: Longhorn is set as the default `StorageClass` so that `PersistentVolumeClaims` without an explicit `storageClassName` use it automatically.

To check storage status:

```bash
kubectl get storageclass
kubectl get pv,pvc -A
```

## Load Balancing (MetalLB)

[MetalLB](https://metallb.universe.tf/) allocates external IP addresses from the pool `10.8.24.102–10.8.24.120` to `LoadBalancer`-type services.

To request a specific IP for a service, annotate it:

```yaml
metadata:
  annotations:
    metallb.universe.tf/loadBalancerIPs: "10.8.24.110"
```

Currently allocated IPs:

| Service | IP |
|---------|-----|
| ArgoCD | 10.8.24.102 |
| Longhorn UI | 10.8.24.105 |

## High Availability (Kube-vip)

[Kube-vip](https://kube-vip.io/) keeps the Kubernetes API server accessible via a virtual IP (`10.8.24.101`) using ARP broadcasts. If the current leader node fails, the VIP migrates to another master node automatically.

The Kube-vip version is controlled by `kube_vip_tag_version` in `cluster/config/group_vars/all.yml`.

## Troubleshooting

**Check K3s service status on a node**:

```bash
sudo systemctl status k3s          # on master
sudo systemctl status k3s-agent    # on agent nodes
sudo journalctl -u k3s -f          # follow logs
```

**Node not joining the cluster**:

- Verify the `k3s_token` in `all.yml` matches on all nodes.
- Ensure the API server endpoint (`10.8.24.101`) is reachable from all nodes.
- Check firewall rules allow TCP 6443 (API) and UDP 8472 (Flannel VXLAN).

**Pod stuck in `Pending`**:

```bash
kubectl describe pod <pod-name> -n <namespace>
# Check for storage (Longhorn) or scheduling issues
kubectl get events -n <namespace> --sort-by='.lastTimestamp'
```

**ArgoCD application out of sync**:

```bash
argocd app sync <app-name>
# or from the UI: click "Sync" on the application card
```
