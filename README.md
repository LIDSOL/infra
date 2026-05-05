# Lidsol Infrastructure

This repository contains the infrastructure as code for LIDSOL. It uses Ansible and Kubernetes to manage the infrastructure.

## Overview

The infrastructure consists of a Kubernetes cluster and a router. The cluster is managed by Ansible and GitOps principles are used to deploy applications to it using ArgoCD.

## Managed Nodes

-   **Kubernetes Cluster:**
    -   `lidsol-master` (192.168.1.100): The master node of the K3s cluster.
    -   `lidsol-node-1` (192.168.1.101): A worker node for the K3s cluster.
-   **Router:**
    -   `router` (192.168.1.1): A network router.

## Directory Structure

-   `.gitmodules`: Defines the git submodules used in this repository.
-   `cluster/`: Contains Ansible playbooks for setting up the Kubernetes cluster.
    -   `k3s-ansible/`: A git submodule containing an Ansible playbook to install K3s.
    -   `argocd.yml`: An Ansible playbook to install ArgoCD on the cluster.
    -   `node.yml`: An Ansible playbook to configure the cluster nodes.
    -   `config/`: Configuration files for the cluster setup, including the Ansible inventory.
-   `gitops/`: Contains the Kubernetes manifests for the applications deployed on the cluster.
-   `mirrors/`: Contains Ansible playbooks for setting up mirrors for Linux Mint.
-   `router/`: Contains Ansible playbooks for configuring the router.

## Services

### Cluster

-   **K3s:** A lightweight Kubernetes distribution.
-   **ArgoCD:** A declarative, GitOps continuous delivery tool for Kubernetes. It is configured to be accessible at `10.8.24.102`.
-   **Unattended Upgrades:** Enabled on the cluster nodes for automatic security updates.

### GitOps Applications

The following applications are deployed on the Kubernetes cluster using ArgoCD:

-   **cert-manager:** Manages TLS certificates in Kubernetes. It is configured with a staging Let's Encrypt issuer.
-   **ingress-nginx:** An Ingress controller for Kubernetes using NGINX as a reverse proxy and load balancer.
-   **drawdb:** A database diagramming tool. It is accessible at `https://db.lidsol.unam.mx`.

### Router

-   **dnsmasq:** Provides DNS and DHCP services.
-   **nftables:** The default firewall framework in modern Linux distributions.
-   **WireGuard:** A fast and modern VPN.
-   **Unattended Upgrades:** Enabled for automatic security updates.
-   **SSH:** Secured by disabling password authentication and allowing only public key authentication.

### Mirrors

-   Systemd timers are set up to periodically fetch updates for Linux Mint ISOs and repositories.

## How to Run

### Prerequisites

1.  **Initialize Git Submodules:**
    ```bash
    git submodule update --init --recursive
    ```
2.  **Install Ansible:** Make sure you have Ansible installed.
3.  **Install Ansible Collections:** You may need to install Ansible collections used in the playbooks (e.g., `ansible.builtin`, `community.general`).

### Router Setup

To configure the router, run the following command:

```bash
ansible-playbook -i router/inventory.yml router/router.yml
```

### Cluster Setup

1.  **Install K3s:**
    Run the `k3s-ansible` playbook. The exact command might vary depending on the playbook's structure, but it should be similar to this:
    ```bash
    ansible-playbook -i cluster/config/hosts.ini cluster/k3s-ansible/site.yml
    ```
2.  **Configure Nodes:**
    ```bash
    ansible-playbook -i cluster/config/hosts.ini cluster/node.yml
    ```
3.  **Install ArgoCD:**
    ```bash
    ansible-playbook -i cluster/config/hosts.ini cluster/argocd.yml
    ```

### Deploying GitOps Applications

The applications in the `gitops/` directory are managed by ArgoCD. To deploy them, you need to configure ArgoCD to point to this repository. This is typically done by creating an `Application` resource in ArgoCD that points to the `gitops/` directory.
