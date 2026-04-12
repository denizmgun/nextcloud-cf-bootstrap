---
# Nextcloud AIO — rendered by 07_configure_nextcloud.sh
# Variables substituted: NC_DOMAIN, NC_DATADIR, NC_TIMEZONE, BACKUP_LOCATION
services:
  nextcloud-aio-mastercontainer:
    image: nextcloud/all-in-one:latest
    init: true
    restart: always
    container_name: nextcloud-aio-mastercontainer
    volumes:
      # AIO internal config volume
      - nextcloud_aio_mastercontainer:/mnt/docker-aio-config
      # Docker socket — read-only; AIO uses it to manage child containers
      - /var/run/docker.sock:/var/run/docker.sock:ro
      # Nextcloud data directory (bind mount)
      - {{NC_DATADIR}}:/mnt/ncdata
      # Backup destination (rclone mount or local path)
      - {{BACKUP_LOCATION}}:/mnt/backup
    ports:
      # AIO admin panel — bound to loopback; exposed only via Cloudflare Tunnel
      - 127.0.0.1:8080:8080
    environment:
      # Apache (Nextcloud) port — reached via Cloudflare Tunnel on port 11000
      - APACHE_PORT=11000
      # Bind Nextcloud to loopback so it is not reachable directly from internet
      - APACHE_IP_BINDING=127.0.0.1
      # Public domain — must match the hostname configured in the tunnel
      - NC_DOMAIN={{NC_DOMAIN}}
      # Absolute path where Nextcloud stores user data inside the container
      - NEXTCLOUD_DATADIR={{NC_DATADIR}}
      # Absolute host path for AIO-managed backups
      - NEXTCLOUD_BACKUP_MOUNTPOINT={{BACKUP_LOCATION}}
      - TZ={{NC_TIMEZONE}}
      - AIO_DISABLE_BACKUP_SECTION=false
      - BACKUP_RESTORE_RETENTION_DAYS=7

volumes:
  nextcloud_aio_mastercontainer:
    name: nextcloud_aio_mastercontainer
