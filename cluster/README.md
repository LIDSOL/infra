# Kubernetes (K3s) Cluster Runbook & Documentation

## 1. Architecture & Components

This cluster runs on virtualized Proxmox infrastructure using a highly available, GitOps-driven architecture.

### Compute (Proxmox VMs)
*   **OS:** Debian 13 (Trixie) Cloud-Init
*   **Specs:** 4GB RAM, 2 Cores, 100GB Virtual Disks (Thin-provisioned on `local-zfs`)
*   **Nodes (K3s v1.35.4+k3s1):**
    *   `k3s-master` (10.8.24.30) - Control Plane / Etcd
    *   `k3s-worker1` (10.8.24.31) - Compute
    *   `k3s-worker2` (10.8.24.32) - Compute
    *   `k3s-worker3` (10.8.24.33) - Compute

### Core Components
*   **Kube-VIP (v1.1.2):** Runs as a DaemonSet to broadcast the Virtual IP (`10.8.24.101`) for highly available Kubernetes API access.
*   **MetalLB (v0.15.3):** Handles Layer 2 load balancing for incoming traffic to cluster services. Deployed via raw manifests.
*   **Longhorn (v1.11.1):** Distributed block storage controller utilizing the 100GB disks at `/var/lib/longhorn`. Deployed via raw manifests.
*   **ArgoCD (Stable):** GitOps controller running as a StatefulSet, responsible for continuously deploying applications in the `gitops` namespace (Nextcloud, DrawDB, Speedtest Tracker, Website).

---

## 2. Node Replacement Procedure (Zero Downtime)

To safely replace or migrate a node without impacting stateful workloads like `nextcloud-db-0`:

**Step 1: Provision the New Node**
1. Clone the Debian 13 Proxmox template and expand the disk to 100GB.
2. Install required storage dependencies via SSH:
   ```bash
   sudo apt-get update && sudo apt-get install -y open-iscsi nfs-common
   sudo systemctl enable --now iscsid
   ```

**Step 2: Join the Cluster**
*   **For a Worker:**
    ```bash
    curl -sfL https://get.k3s.io | K3S_TOKEN="<CLUSTER_TOKEN>" sh -s - agent --server https://10.8.24.101:6443
    ```

**Step 3: Migrate Workloads**
1. Mark the old node as unschedulable:
   ```bash
   kubectl cordon <OLD_NODE_NAME>
   ```
2. Gracefully evict the pods:
   ```bash
   kubectl drain <OLD_NODE_NAME> --ignore-daemonsets --delete-emptydir-data --force
   ```
3. **CRITICAL:** Check the Longhorn UI. Ensure all replicas previously on the old node have finished rebuilding and are `Healthy` on the new node.

**Step 4: Decommission**
```bash
kubectl delete node <OLD_NODE_NAME>
```

---

## 3. Upgrade Procedures

Always upgrade the foundation (K3s) before the network and storage tools.

### A. Upgrading K3s
**Upgrade Master First:**
```bash
curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION="<NEW_VERSION>" sh -s - server
```
**Upgrade Workers (One by one):**
```bash
curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION="<NEW_VERSION>" K3S_TOKEN="<TOKEN>" sh -s - agent --server https://10.8.24.101:6443
```

### B. Upgrading Networking (Kube-VIP & MetalLB)
**Kube-VIP:** Update the DaemonSet image directly.
```bash
kubectl set image daemonset/kube-vip-ds -n kube-system kube-vip=ghcr.io/kube-vip/kube-vip:<NEW_VERSION>
```
**MetalLB:** Apply the latest native manifest. Kubernetes will automatically patch the missing annotations.
```bash
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/<NEW_VERSION>/config/manifests/metallb-native.yaml
```

### C. Upgrading Storage (Longhorn)
*Verify all volumes are healthy before proceeding.*
```bash
kubectl apply -f https://raw.githubusercontent.com/longhorn/longhorn/<NEW_VERSION>/deploy/longhorn.yaml
```
*(Note: If UI pods get stuck in an `Error` state after an upgrade, force delete them with `kubectl delete pod <name> -n longhorn-system --force --grace-period=0` to spawn fresh ones).*

### D. Upgrading ArgoCD
Due to massive Custom Resource Definitions (CRDs) in newer ArgoCD versions, you **must** use Server-Side Apply to bypass Kubernetes annotation size limits.
```bash
kubectl apply --server-side --force-conflicts -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl rollout restart statefulset argocd-application-controller -n argocd
```

---

## 4. How to Check Cluster State

Use these commands to perform a complete system audit.

**Check Compute Health:**
```bash
# All nodes should be 'Ready' and on the same version
kubectl get nodes
```

**Check API VIP Health:**
```bash
# Ensure 1 instance of kube-vip is running
kubectl get daemonset kube-vip-ds -n kube-system
```

**Check Storage Health:**
```bash
# Ensure ROBUSTNESS is 'healthy' and STATE is 'attached'
kubectl get volumes.longhorn.io -n longhorn-system
```

**Check Application Workloads:**
```bash
# Verify Nextcloud, DrawDB, and Website are 'Running'
kubectl get pods -n gitops -o wide
```

**Check GitOps Sync Status:**
```bash
# Ensure applications match the Git repository
kubectl get applications -n argocd
```
