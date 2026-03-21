# GitOps Deployments

This document describes the GitOps workflow used by LIDSOL to deploy and manage applications on the Kubernetes cluster. All Kubernetes manifests are stored in the `gitops/` directory and continuously reconciled by [ArgoCD](https://argo-cd.readthedocs.io/).

## Table of Contents

- [Overview](#overview)
- [How GitOps Works Here](#how-gitops-works-here)
- [Deployed Applications](#deployed-applications)
- [Adding a New Application](#adding-a-new-application)
- [TLS / HTTPS](#tls--https)
- [Ingress](#ingress)
- [Updating a Container Image](#updating-a-container-image)
- [Troubleshooting](#troubleshooting)

## Overview

```
GitHub repository (LIDSOL/infra)
        │
        │  git push to main
        ▼
  gitops/ directory
        │
        │  ArgoCD polls every 3 minutes (or webhook)
        ▼
  Kubernetes cluster
  (auto-sync, auto-prune, self-heal)
```

ArgoCD monitors the `gitops/` directory of the `main` branch. Any change merged to `main` is automatically applied to the cluster within minutes, without manual `kubectl apply` commands.

## How GitOps Works Here

The ArgoCD `Application` resource that drives the sync is defined in `cluster/argo-config/default-manifest.yml`. Key settings:

| Setting | Value | Meaning |
|---------|-------|---------|
| Source repo | `https://github.com/LIDSOL/infra` | This repository |
| Source path | `gitops/` | Only manifests under this folder are synced |
| Target branch | `main` | Changes on `main` trigger a sync |
| Auto-sync | enabled | ArgoCD applies changes automatically |
| Auto-prune | enabled | Deleted manifests are removed from the cluster |
| Self-heal | enabled | Manual `kubectl` edits are reverted back to the declared state |
| Destination | `https://kubernetes.default.svc` | In-cluster API server |
| Namespace | `gitops` | Default namespace for resources without an explicit namespace |

## Deployed Applications

### LIDSOL Website

| Property | Value |
|----------|-------|
| Manifest | `gitops/website-deployment.yaml` |
| Image | `ghcr.io/lidsol/sitio-web-lidsol:master` |
| Replicas | 3 |
| Namespace | `gitops` |
| Public URL | `https://lidsol.unam.mx` |

Static website for LIDSOL, served through Ingress-Nginx with a Let's Encrypt TLS certificate.

### Nextcloud

| Property | Value |
|----------|-------|
| Manifest | `gitops/nextcloud-deployment.yaml` |
| Namespace | `gitops` |
| Storage (DB) | 20 Gi (Longhorn) |
| Storage (Data) | 80 Gi (Longhorn) |

Collaborative file-sharing suite backed by MariaDB. Persistent volumes are provisioned automatically by Longhorn.

### Cert-Manager

| Property | Value |
|----------|-------|
| Manifest | `gitops/certmanager-deployment.yaml` |
| Namespace | `cert-manager` |

Automates TLS certificate issuance and renewal using Let's Encrypt. See [TLS / HTTPS](#tls--https).

### Ingress-Nginx

| Property | Value |
|----------|-------|
| Manifest | `gitops/ingress-deployment.yaml` |
| Version | v1.13.2 |
| Namespace | `ingress-nginx` |
| HTTP port | 80 |
| HTTPS port | 443 |

Reverse proxy and load balancer for all HTTP/HTTPS traffic entering the cluster. See also `gitops/ExplicacionIngress.md` (Spanish) for additional details on the ingress controller configuration and how to write `Ingress` resources.

### HTTPS Issuer

| Property | Value |
|----------|-------|
| Manifest | `gitops/https-issuer-deployment.yaml` |
| Type | `ClusterIssuer` |
| Provider | Let's Encrypt (ACME) |

Defines the `ClusterIssuer` resources (`letsencrypt-staging` and `letsencrypt-prod`) used by cert-manager to obtain TLS certificates.

### Longhorn UI

| Property | Value |
|----------|-------|
| Manifest | `gitops/longhorn-ui-deployment.yaml` |
| IP | 10.8.24.105 |
| Port | 80 |

Exposes the Longhorn storage dashboard as a `LoadBalancer` service on the internal network.

### DrawDB

| Property | Value |
|----------|-------|
| Manifest | `gitops/drawdb-deployment.yaml` |
| Namespace | `gitops` |

Web-based database schema design tool.

### Speedtest Tracker

| Property | Value |
|----------|-------|
| Manifest | `gitops/speedtest-tracker-deployment.yaml` |
| Namespace | `gitops` |

Continuously monitors and records internet connection speed.

## Adding a New Application

1. Create a manifest file in `gitops/`:
   ```bash
   touch gitops/myapp-deployment.yaml
   ```

2. Write the manifest. A minimal example:

   ```yaml
   ---
   apiVersion: apps/v1
   kind: Deployment
   metadata:
     name: myapp
     namespace: gitops
   spec:
     replicas: 1
     selector:
       matchLabels:
         app: myapp
     template:
       metadata:
         labels:
           app: myapp
       spec:
         containers:
           - name: myapp
             image: myorg/myapp:latest
             resources:
               requests:
                 cpu: "100m"
                 memory: "128Mi"
               limits:
                 cpu: "500m"
                 memory: "256Mi"
   ---
   apiVersion: v1
   kind: Service
   metadata:
     name: myapp
     namespace: gitops
   spec:
     selector:
       app: myapp
     ports:
       - port: 80
         targetPort: 8080
   ```

3. Add an `Ingress` resource if the app needs external HTTP/HTTPS access (see [Ingress](#ingress) below).

4. Validate the manifest before committing:
   ```bash
   kubectl apply --dry-run=client -f gitops/myapp-deployment.yaml
   ```

5. Commit and open a pull request. After merge to `main`, ArgoCD applies the manifest automatically.

## TLS / HTTPS

Certificates are issued by [cert-manager](https://cert-manager.io/) using Let's Encrypt.

To enable HTTPS for an ingress, add the cert-manager annotation and a `tls` block:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: myapp
  namespace: gitops
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
spec:
  ingressClassName: nginx
  tls:
    - hosts:
        - myapp.lidsol.unam.mx
      secretName: myapp-tls
  rules:
    - host: myapp.lidsol.unam.mx
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: myapp
                port:
                  number: 80
```

> Use `letsencrypt-staging` during development to avoid rate limits; switch to `letsencrypt-prod` for production.

## Ingress

All ingress traffic is handled by **ingress-nginx** (v1.13.2). The controller listens on the cluster node ports and routes traffic based on `Ingress` resources.

For detailed examples and configuration options, see `gitops/ExplicacionIngress.md`.

Common annotations:

| Annotation | Example | Purpose |
|-----------|---------|---------|
| `nginx.ingress.kubernetes.io/rewrite-target` | `/` | URL rewriting |
| `nginx.ingress.kubernetes.io/ssl-redirect` | `"true"` | Force HTTPS |
| `nginx.ingress.kubernetes.io/proxy-body-size` | `"50m"` | Increase upload limit |
| `cert-manager.io/cluster-issuer` | `letsencrypt-prod` | Request a TLS certificate |

## Updating a Container Image

Images in `gitops/` manifests can be updated in two ways:

1. **Manual update**: Edit the `image:` field in the manifest file, commit, and push to `main`. ArgoCD will detect the change and perform a rolling update.

2. **ArgoCD Image Updater** (configured by `argocd.yml`): Automatically detects new tags in the container registry and commits updated image tags back to the repository. Configure the update policy with annotations on the `Application` resource.

## Troubleshooting

**Check ArgoCD application status**:

```bash
# List all applications
kubectl get applications -n argocd

# Describe a specific application
kubectl describe application <app-name> -n argocd
```

**Force a manual sync**:

```bash
# Using kubectl
kubectl patch application <app-name> -n argocd \
  --type merge -p '{"operation":{"initiatedBy":{"username":"admin"},"sync":{}}}'

# Using argocd CLI
argocd app sync <app-name>
```

**Inspect events on a namespace**:

```bash
kubectl get events -n gitops --sort-by='.lastTimestamp'
```

**View logs for a pod**:

```bash
kubectl logs -n gitops deployment/myapp --tail=100 -f
```

**CrashLoopBackOff or ImagePullBackOff**:

```bash
kubectl describe pod -n gitops <pod-name>
# Look at Events section for the root cause
```
