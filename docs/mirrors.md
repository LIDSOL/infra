# Linux Distribution Mirrors

This document describes the Linux distribution mirror infrastructure hosted by LIDSOL at `lidsol.fi-b.unam.mx`. Mirrors are managed by the `mirrors` Ansible role located at `public-server/mirrors/`.

## Table of Contents

- [Overview](#overview)
- [Hosted Distributions](#hosted-distributions)
- [Role Structure](#role-structure)
- [Variables](#variables)
- [Deploying the Mirrors Role](#deploying-the-mirrors-role)
- [Mirror Sync Tools](#mirror-sync-tools)
  - [AlmaLinux](#almalinux)
  - [ArchLinux](#archlinux)
  - [Debian](#debian)
  - [Fedora](#fedora)
  - [Linux Mint](#linux-mint)
- [Nginx Configuration](#nginx-configuration)
- [rsync Daemon](#rsync-daemon)
- [Adding a New Mirror](#adding-a-new-mirror)
- [Troubleshooting](#troubleshooting)

## Overview

LIDSOL mirrors several popular Linux distributions to provide fast, local package downloads for users at UNAM. The mirrors are synchronized from upstream sources using `rsync` and custom sync scripts, and served over HTTP/HTTPS by Nginx.

```
Upstream mirror sources (internet)
         │
         │  rsync / ftpsync
         ▼
/srv/<distro>/   (disk storage on mirror server)
         │
         │  Nginx (with per-mirror access/error logs)
         ▼
lidsol.fi-b.unam.mx/<distro>/
```

A dedicated `mirrors` OS user owns all mirror data under `/srv/`.

## Hosted Distributions

| Distribution | Local Path | Upstream Source |
|-------------|-----------|----------------|
| AlmaLinux | `/srv/almalinux/` | rsync.repo.almalinux.org |
| ArchLinux | `/srv/archlinux/` | mirror.rackspace.com |
| Debian | `/srv/debian/` | ftp.us.debian.org (ftpsync) |
| Debian CD | `/srv/debian-cd/` | cdimage.debian.org |
| Fedora | `/srv/fedora/` | dl.fedoraproject.org |
| Linux Mint | `/srv/linux-mint/` | rsync.linuxmint.com |
| Linux Mint ISO | `/srv/linux-mint-cd/` | rsync.linuxmint.com::linuxmint-cd |

## Role Structure

```
public-server/mirrors/
├── tasks/
│   ├── main.yaml              # Orchestrator: includes all subtasks
│   ├── almalinux.yaml         # AlmaLinux sync setup
│   ├── archlinux.yaml         # ArchLinux sync setup
│   ├── debian.yaml            # Debian & Debian-CD sync setup
│   ├── fedora.yaml            # Fedora sync setup
│   ├── linux-mint.yaml        # Linux Mint sync setup
│   ├── nginx.yaml             # Nginx virtual host configuration
│   └── rsync-daemon.yaml      # rsync daemon setup
├── files/distros/
│   ├── AlmaLinux/             # AlmaLinux sync scripts and config
│   ├── ArchLinux/             # ArchLinux sync scripts
│   ├── Debian/
│   │   ├── repository/ftpsync/  # Debian ftpsync tool
│   │   └── scripts/           # Mirror check script
│   ├── Fedora/                # Fedora sync scripts and config
│   └── LinuxMint/             # Linux Mint sync scripts
├── handlers/
├── templates/                 # Jinja2 templates (nginx vhosts, cron entries, etc.)
└── vars/
    └── main.yml               # Mirror paths, logging, distro metadata
```

## Variables

All mirror-related variables are defined in `public-server/mirrors/vars/main.yml`.

Key variables:

| Variable | Description |
|----------|-------------|
| `mirrors_base_dir` | Base directory for all mirrors (default: `/srv`) |
| `mirrors_user` | OS user owning mirror data (default: `mirrors`) |
| `mirrors_log_dir` | Directory for per-mirror logs |
| Distro-specific vars | Upstream rsync URLs, local paths, bandwidth limits |

## Deploying the Mirrors Role

```bash
# Deploy only the mirrors role
ansible-playbook -i public-server/inventory.yml public-server/main.yaml \
  --limit servers --tags mirrors

# Deploy mirrors + nginx together
ansible-playbook -i public-server/inventory.yml public-server/main.yaml \
  --limit servers --tags mirrors,nginx
```

After deployment, the cron jobs / systemd timers for each distribution will be configured and sync will begin on schedule.

## Mirror Sync Tools

### AlmaLinux

- **Script/tool**: Custom rsync wrapper
- **Source**: `public-server/mirrors/files/distros/AlmaLinux/`
- **Upstream**: `rsync://rsync.repo.almalinux.org/almalinux/`
- **Local path**: `/srv/almalinux/`
- Sync is scheduled via a cron job (or systemd timer) installed by the `almalinux.yaml` task.

### ArchLinux

- **Script**: `archlinux-syncrepo.sh`
- **Source**: `public-server/mirrors/files/distros/ArchLinux/repository/scripts/`
- **Upstream**: `rsync://mirror.rackspace.com/archlinux/`
- **Local path**: `/srv/archlinux/`
- The script follows the [ArchLinux Mirror Guidelines](https://wiki.archlinux.org/title/DeveloperWiki:NewMirrors).

### Debian

- **Tool**: [ftpsync](https://salsa.debian.org/mirror-team/archvsync) (included at `public-server/mirrors/files/distros/Debian/repository/ftpsync/`)
- **Local paths**: `/srv/debian/`, `/srv/debian-cd/`
- **Check script**: `public-server/mirrors/files/distros/Debian/repository/scripts/debian-mirror-sync-check.sh` — validates that the mirror is up to date and reports errors.

Running the check script manually:

```bash
sudo -u mirrors /home/mirrors/debian/scripts/debian-mirror-sync-check.sh
```

### Fedora

- **Source**: `public-server/mirrors/files/distros/Fedora/`
- **Upstream**: `rsync://dl.fedoraproject.org/fedora-enchilada/linux/`
- **Local path**: `/srv/fedora/`
- Includes configuration to sync only the actively supported Fedora releases.

### Linux Mint

- **Scripts**:
  - `linuxmint-mirror-sync.sh` — syncs package repositories
  - `linuxmint-cd-sync.sh` — syncs ISO images
- **Source**: `public-server/mirrors/files/distros/LinuxMint/`
- **Upstream**: `rsync://rsync.linuxmint.com/`
- **Local paths**: `/srv/linux-mint/`, `/srv/linux-mint-cd/`

## Nginx Configuration

The `nginx.yaml` task deploys a virtual host configuration for the mirrors. Each distribution is accessible at:

```
http://lidsol.fi-b.unam.mx/<distro>/
https://lidsol.fi-b.unam.mx/<distro>/
```

Each distribution has its own Nginx `access_log` and `error_log` for easier monitoring. Log paths are configured in `vars/main.yml`.

To check the current Nginx mirror configuration on the server:

```bash
sudo nginx -T | grep -A 20 "server_name lidsol.fi-b.unam.mx"
sudo tail -f /var/log/nginx/mirrors-access.log
```

## rsync Daemon

The `rsync-daemon.yaml` task sets up an `rsyncd` service so that other mirror operators can pull from LIDSOL. This is important for participating in the wider mirror network.

The rsync daemon configuration restricts which modules (paths) are shared, sets bandwidth limits, and requires read-only access.

To check rsync daemon status:

```bash
sudo systemctl status rsync
cat /etc/rsyncd.conf
```

## Adding a New Mirror

1. **Create the task file**: Add `public-server/mirrors/tasks/<distro>.yaml` following the pattern of an existing task (e.g., `almalinux.yaml`).

2. **Add variables**: Add the new distro's variables (path, upstream URL, log files) to `public-server/mirrors/vars/main.yml`.

3. **Add sync scripts**: Place any sync scripts or tools in `public-server/mirrors/files/distros/<Distro>/`.

4. **Update nginx.yaml**: Add a new `location` block for the distro's path.

5. **Update rsync-daemon.yaml**: Add a new module to `rsyncd.conf` if the distro should be available for re-mirroring.

6. **Update this document**: Add the new distribution to the [Hosted Distributions](#hosted-distributions) table.

7. **Provision disk space**: Ensure the server has sufficient disk space. Before deploying, estimate the mirror size from the upstream documentation.

8. **Test the sync**:
   ```bash
   ansible-playbook -i public-server/inventory.yml public-server/main.yaml \
     --limit servers --tags mirrors --check
   ```

## Troubleshooting

**Sync script fails with rsync error**:

```bash
# Check upstream reachability
rsync --list-only rsync://<upstream-host>/<module>/

# Run the sync manually as the mirrors user
sudo -u mirrors /home/mirrors/<distro>/scripts/sync.sh
```

**Nginx returns 403 Forbidden for a mirror path**:

```bash
# Check file permissions
ls -la /srv/<distro>/
# The mirrors user must own the files; the Nginx worker must be able to read them
sudo chown -R mirrors:mirrors /srv/<distro>/
sudo chmod -R o+r /srv/<distro>/
```

**Mirror is out of date**:

```bash
# Check when the last sync ran
sudo journalctl -u rsync -f
cat /var/log/mirrors/<distro>-sync.log | tail -50

# Force an immediate sync
sudo systemctl start <distro>-mirror-sync.timer   # or run the script directly
```

**Disk space exhausted**:

```bash
df -h /srv
du -sh /srv/*    # Check per-distro usage
# Consider pruning old releases or adding storage
```
