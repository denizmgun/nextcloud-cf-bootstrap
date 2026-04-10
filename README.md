# nextcloud-cf-bootstrap

Bootstrap a self-hosted [Nextcloud AIO](https://github.com/nextcloud/all-in-one) instance on a fresh Ubuntu 24.04 VM, exposed to the internet via a [Cloudflare Tunnel](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/), with optional remote backup storage via rclone.

**No git required on the target machine.**

---

## Requirements

- Ubuntu 24.04 LTS (amd64 or arm64)
- Root or sudo access
- A domain registered and delegated to Cloudflare nameservers
- A Cloudflare Tunnel token ([create one here](https://one.dash.cloudflare.com) → Networks → Tunnels)

---

## Quick install

Download and run the bootstrap in one command:

```bash
curl -fsSL https://github.com/YOUR_USERNAME/nextcloud-cf-bootstrap/archive/refs/heads/main.tar.gz \
  | tar -xz \
  && sudo bash nextcloud-cf-bootstrap-main/bootstrap.sh
```

> Replace `YOUR_USERNAME` with the GitHub username or organisation that hosts this repo.

---

## Step-by-step install

If you prefer to inspect the scripts before running:

```bash
# 1. Download and extract
curl -fsSL https://github.com/YOUR_USERNAME/nextcloud-cf-bootstrap/archive/refs/heads/main.tar.gz \
  | tar -xz

# 2. Enter the directory
cd nextcloud-cf-bootstrap-main

# 3. (Optional) review scripts
ls scripts/

# 4. Run
sudo bash bootstrap.sh
```

### Dry run

Print every step that would be executed without making any changes:

```bash
sudo bash bootstrap.sh --dry-run
```

---

## What the bootstrap does

Each numbered script is independently runnable. The master script calls them in sequence and skips rclone steps if you opt out.

| Step | Script | What it does |
|------|--------|--------------|
| 01 | `01_install_docker.sh` | Installs Docker CE from the official repository |
| 02 | `02_install_cloudflared.sh` | Installs cloudflared (arch-aware: amd64 / arm64) |
| 03 | `03_prompt_rclone.sh` | Asks whether you want remote backup storage |
| 04 | `04_install_rclone.sh` | Installs rclone + FUSE3 *(skipped if you said no)* |
| 05 | `05_configure_tunnel.sh` | Collects your tunnel token and hostnames; writes `~/.cloudflared/config.yml` |
| 06 | `06_configure_rclone.sh` | Interactive rclone remote setup; creates a systemd mount unit *(skipped if you said no)* |
| 07 | `07_configure_nextcloud.sh` | Collects data/backup paths; renders `~/.nextcloud/docker-compose.yml` |
| 08 | `08_connect_tunnel.sh` | Installs cloudflared as a systemd service and verifies the tunnel is live |
| 09 | `09_run_nextcloud.sh` | Pulls and starts Nextcloud AIO; waits for the container to become healthy |
| 10 | `10_secure_admin.sh` | Retrieves the AIO initial passphrase; guides Cloudflare Access setup |

### Running a single step

```bash
sudo bash scripts/05_configure_tunnel.sh
```

---

## Files written

| Path | Contents | Mode |
|------|----------|------|
| `~/.nextcloud/.env` | All non-secret config values | `600` |
| `~/.nextcloud/docker-compose.yml` | Rendered Nextcloud AIO compose file | `600` |
| `~/.cloudflared/config.yml` | Tunnel ingress config | `600` |
| `~/.cloudflared/.env` | Tunnel token (never written elsewhere) | `600` |
| `/etc/systemd/system/rclone-backup-mount.service` | rclone systemd mount unit | system default |

---

## After the bootstrap

1. Open the AIO admin panel at `https://<ADMIN_HOSTNAME>`
2. Log in with the passphrase printed by step 10 (also saved in `~/.nextcloud/.env`)
3. Follow the AIO setup wizard to activate Nextcloud and any bundled apps
