---
title: "Terminus"
summary: "Terminus server stack on Unraid — manages the TRMNL e-ink display, deployed via Docker Compose"
tags: [unraid, services, trmnl, cronicle, screen, docker]
template: "system"
ip-addresses:
  terminus: 192.168.0.44:2300
---

# Terminus

Terminus is the server stack running on Unraid that manages the TRMNL e-ink
display. Deployed via Docker Compose with a PostgreSQL database and Valkey
cache.

## Location

| Item | Value |
|------|-------|
| Host | Unraid ([ip-address: terminus], br0) |
| Compose | `/boot/config/plugins/compose.manager/projects/terminus/compose.yaml` |
| Secrets mount | `/mnt/user/appdata/cronicle-trmnl-secrets:/mnt/user/appdata/cronicle-trmnl-secrets:ro` |

## Status

Verify with `ssh unraid "docker ps --filter name=terminus"` and `ssh unraid "docker logs terminus --tail 10"`.

The container name is lowercase `terminus` (not `Terminus`).

## Chromium Version Pinning

The Dockerfile pins Chromium version to avoid breakage from upstream
updates. The `terminus-unraid` repo CHANGELOG documents this pinning
in v0.1.1.

Verify: `ssh unraid "docker exec terminus chromium --version"`.

## Database Migrations

The Terminus stack uses PostgreSQL with a persistent data volume. When
upgrading the Terminus image, the new code may expect schema columns that
don't exist in the old database. The container entrypoint does not run
`hanami db migrate` automatically.

Manual migration (add missing columns directly):

```sh
ssh unraid "docker exec terminus-database-1 psql -U terminus -d terminus_dev -c 'ALTER TABLE device ADD COLUMN IF NOT EXISTS api_key varchar;'"
```

Known schema additions:

- `api_key` column on `device` table — required by current Terminus version for device polling endpoint

## Stale NFS Bind Mount

The `croniclev2` container bind-mounts `/mnt/user/appdata/vm-sync`
(the NFS export from ai-vm-1). When the NFS mount drops and reconnects
on the Unraid host, Docker bind mounts referencing the NFS path become
stale — the container sees the directory structure but none of the
current file contents. This causes all `shellrootplug` jobs to fail
with exit code 127 (file not found).

Symptom: TRMNL screen pushes stop working. Cronicle job history shows
repeated FAIL(127) for `TRMNL Main Screen`.

`docker restart croniclev2` on Unraid re-resolves the bind mount.

Automated watchdog: the **Cronicle NFS Mount Watchdog** job
(`emsba121g02`) runs every 5 minutes, checks for a sentinel file in
the NFS mount, and restarts `croniclev2` if the bind mount is stale.
Script: `jobs/infrastructure/cronicle-nfs-watchdog.sh`.

## Notes

- TRMNL firmware updates can change the API contract — test after
  firmware upgrades
- The `terminus-unraid` repo is private under `adinballew` on GitHub
