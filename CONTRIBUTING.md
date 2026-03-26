# Contributing to LIDSOL Infrastructure

Thank you for your interest in contributing to the LIDSOL infrastructure repository! This document explains how to get started, what kinds of contributions are welcome, and how the review process works.

## Table of Contents

- [Code of Conduct](#code-of-conduct)
- [Ways to Contribute](#ways-to-contribute)
- [Getting Started](#getting-started)
- [Development Workflow](#development-workflow)
- [Making Changes](#making-changes)
  - [Ansible Playbooks and Roles](#ansible-playbooks-and-roles)
  - [Kubernetes Manifests (GitOps)](#kubernetes-manifests-gitops)
  - [Documentation](#documentation)
- [Commit Messages](#commit-messages)
- [Pull Request Process](#pull-request-process)
- [Reporting Issues](#reporting-issues)
- [Contact](#contact)

## Code of Conduct

This project follows UNAM's community standards. We expect all contributors to be respectful, constructive, and collaborative. Harassment or discrimination of any kind will not be tolerated.

## Ways to Contribute

- **Bug reports**: Open an issue describing a misconfiguration, broken deployment, or unexpected behavior.
- **Feature requests**: Suggest new services, roles, or infrastructure improvements.
- **Documentation**: Improve or translate any documentation file.
- **Ansible roles**: Add new roles or improve existing ones (security, mirrors, network, etc.).
- **Kubernetes manifests**: Add new application deployments to `gitops/` or tune existing ones.
- **Security improvements**: Harden configurations, reduce attack surfaces, or update vulnerable components.

## Getting Started

### 1. Fork and clone

```bash
# Fork the repo on GitHub, then:
git clone --recurse-submodules https://github.com/<your-username>/infra.git
cd infra
```

### 2. Install prerequisites

| Tool | Minimum Version |
|------|----------------|
| [Ansible](https://docs.ansible.com/ansible/latest/installation_guide/) | 2.14 |
| [kubectl](https://kubernetes.io/docs/tasks/tools/) | 1.28 |
| [Git](https://git-scm.com/) | 2.40 |
| Python | 3.10 |

Install Ansible collections used in this repo:

```bash
ansible-galaxy collection install community.general
```

### 3. Set up a test environment

> **Important**: Never test changes directly against production nodes without first verifying them in a safe environment. Use local VMs (e.g., with Vagrant or Multipass) or dedicated test machines.

```bash
# Example: spin up test VMs with multipass
multipass launch --name test-node --cpus 2 --memory 2G
```

## Development Workflow

```
fork → clone → branch → change → test → commit → push → pull request
```

1. Create a branch from `main`:
   ```bash
   git checkout -b feat/my-feature
   ```
2. Make your changes (see [Making Changes](#making-changes) below).
3. Test your changes in a non-production environment.
4. Commit your changes following the [commit message guidelines](#commit-messages).
5. Push and open a pull request against `main`.

## Making Changes

### Ansible Playbooks and Roles

- Follow the standard [Ansible best practices](https://docs.ansible.com/ansible/latest/tips_tricks/ansible_tips_tricks.html).
- Keep tasks idempotent: running a playbook multiple times must always produce the same result.
- Use **roles** for logically grouped tasks (e.g., `security`, `nginx`, `mirrors`).
- Store sensitive values (passwords, tokens, keys) in **Ansible Vault** — never commit them in plain text.
- Use descriptive `name:` fields on every task.
- Prefer YAML block scalars over long single-line strings.
- Add or update the relevant `docs/` file when introducing a new role or changing an existing one significantly.

**Running a playbook in check mode** (dry run, no changes applied):

```bash
ansible-playbook -i public-server/inventory.yml public-server/main.yaml --check
```

**Limiting execution to a single host or role**:

```bash
# Single host
ansible-playbook -i public-server/inventory.yml public-server/main.yaml --limit mirrors

# Single tag
ansible-playbook -i public-server/inventory.yml public-server/main.yaml --tags nginx
```

**Linting Ansible files**:

```bash
pip install ansible-lint
ansible-lint public-server/main.yaml
```

### Kubernetes Manifests (GitOps)

All Kubernetes manifests live in `gitops/`. ArgoCD watches this directory and automatically applies changes when they are merged to `main`.

- One manifest file per application (e.g., `gitops/myapp-deployment.yaml`).
- Always specify resource `requests` and `limits` for CPU and memory.
- Use `Namespace` resources within the manifest when a dedicated namespace is needed.
- Prefer `ClusterIssuer` and `Certificate` resources from cert-manager for TLS — do not store TLS secrets in the repository.
- For `LoadBalancer` services that require a static IP from MetalLB, annotate the service with the desired IP:
  ```yaml
  metadata:
    annotations:
      metallb.universe.tf/loadBalancerIPs: "10.8.24.1XX"
  ```

**Validate manifests before committing**:

```bash
kubectl apply --dry-run=client -f gitops/myapp-deployment.yaml
```

### Documentation

- Documentation lives in `docs/` (detailed per-component guides) and in the root `README.md` and `CONTRIBUTING.md`.
- Write in English; Spanish is also acceptable for documents that are primarily read by the local team.
- Use [Markdown](https://www.markdownlang.org/). Keep lines under 120 characters.
- Update the table of contents in any file you modify if it has one.
- Reference related files with relative links (e.g., `[cluster.md](docs/cluster.md)`).

## Commit Messages

Follow the [Conventional Commits](https://www.conventionalcommits.org/) specification:

```
<type>(<scope>): <short summary>

[optional body]

[optional footer]
```

**Types**:

| Type | When to use |
|------|------------|
| `feat` | New feature or new Ansible role |
| `fix` | Bug fix or misconfiguration correction |
| `docs` | Documentation-only changes |
| `refactor` | Code restructuring without behavior change |
| `chore` | Dependency updates, minor maintenance |
| `security` | Security-related hardening or patch |

**Examples**:

```
feat(mirrors): add Fedora mirror sync role

fix(router): correct nftables masquerade rule for WAN interface

docs(cluster): document MetalLB IP range configuration

security(ssh): disable root login in sshd hardening task
```

## Pull Request Process

1. Ensure your branch is up to date with `main`:
   ```bash
   git fetch origin
   git rebase origin/main
   ```
2. Open a pull request against `main` on GitHub.
3. Fill in the pull request template:
   - Describe **what** changed and **why**.
   - List any manual steps required (e.g., rotating a secret, running a migration).
   - Reference related issues with `Closes #<issue-number>`.
4. At least **one maintainer review** is required before merging.
5. All checks (if any CI workflows are configured) must pass.
6. The PR author is responsible for resolving review comments.
7. Squash or rebase commits before merging if the history is noisy.

> **Production changes**: Any change that will affect production infrastructure (playbooks, K8s manifests) must be tested in a staging or dev environment first and documented in the PR description.

## Reporting Issues

Use the [GitHub Issues](https://github.com/LIDSOL/infra/issues) tracker to report bugs or request features.

When reporting a bug, please include:

- A clear title and description of the problem.
- Steps to reproduce (which playbook/command was run, against which host).
- Expected behavior vs. actual behavior.
- Relevant log output or error messages.
- Environment details (OS, Ansible version, Kubernetes version if applicable).

## Contact

- **Email**: lidsol-info@proton.me
- **GitHub**: [@LIDSOL](https://github.com/LIDSOL)
- **Website**: [lidsol.unam.mx](https://lidsol.unam.mx)
