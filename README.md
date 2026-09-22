# Terminus for Unraid — All-in-One Docker Image

A single-container deployment of [Terminus](https://github.com/usetrmnl/terminus) bundled with PostgreSQL 18 and Valkey 9, designed for Unraid.

## What's Inside

| Component | Version | Purpose |
|-----------|---------|---------|
| Terminus | latest | Ruby Hanami web app + Sidekiq worker |
| PostgreSQL | 18 | Database for Terminus |
| Valkey | 9 | Key-value store (Redis-compatible) for Sidekiq |

All three processes are managed by **supervisord** within a single container.

## Quick Start

1. **Create a private GitHub repo** named `terminus-unraid` under your account.
2. Push this folder to the repo.
3. Enable GitHub Actions — the CI workflow builds and publishes to GHCR automatically.
4. In Unraid, add the template from `templates/terminus-unraid.xml` via **Docker > Add Container > Template**.
5. Set the required passwords/secrets (see below).
6. Start the container and access Terminus at `http://your-unraid-ip:2300`.

## Required Configuration

Set these on first run via the Unraid template:

| Variable | Description | Example |
|----------|-------------|---------|
| `POSTGRES_PASSWORD` | PostgreSQL password | (strong password) |
| `VALKEY_PASSWORD` | Valkey/Redis password | (strong password) |
| `APP_SECRET` | Hanami app secret | (32+ hex chars) |
| `API_URI` | External URL for API callbacks | `http://192.168.0.40:2300` |

## Volume Mounts

| Host Path | Container Path | Purpose |
|-----------|----------------|---------|
| `/mnt/user/appdata/terminus-unraid/database` | `/var/lib/postgresql/18/docker` | PostgreSQL data |
| `/mnt/user/appdata/terminus-unraid/keyvalue` | `/var/valkey` | Valkey persistence |
| `/mnt/user/appdata/terminus-unraid/fonts` | `/usr/share/fonts/terminus` | Custom fonts |
| `/mnt/user/appdata/terminus-unraid/uploads` | `/app/public/uploads` | User uploads |

## Ports

| Port | Purpose |
|------|---------|
| 2300 | Terminus web UI |

## Architecture

```
┌──────────────────────────────────────────┐
│           Container (supervisord)          │
│                                            │
│  ┌─────────────┐  ┌────────┐  ┌─────────┐ │
│  │  PostgreSQL  │  │ Valkey │  │ Terminus│ │
│  │     18       │  │   9    │  │  Web    │ │
│  └─────────────┘  └────────┘  └─────────┘ │
│                                  ┌────────┐│
│                                  │ Sidekiq││
│                                  │ Worker ││
│                                  └────────┘│
└──────────────────────────────────────────┘
```

## CI/CD

GitHub Actions (`.github/workflows/ci.yml`) builds and pushes to `ghcr.io/adinballew/terminus-unraid` on every push to `main`. Tag releases with `v1.0.0` to create versioned images. A `test` job runs first; run it locally with `ok=0; for t in tests/test_*.sh; do bash "$t" || ok=1; done; exit $ok`.

### Required GitHub Secrets

| Secret | Description |
|--------|-------------|
| `GITHUB_TOKEN` | Auto-provided by GitHub Actions (no setup needed) |

No additional secrets are required — `GITHUB_TOKEN` is automatically available.

## File Structure

```
terminus-unraid/
├── .github/workflows/
│   └── ci.yml              # CI/CD pipeline
├── config/
│   ├── supervisord.conf    # Process manager config
│   └── valkey.conf         # Valkey config
├── scripts/
│   ├── entrypoint.sh      # Init & startup script
│   ├── set-valkey-password.sh # Writes requirepass into valkey.conf
│   ├── migrate.sh         # Runs pending DB migrations (supervisord one-shot)
│   └── wait-for-migration.sh # Gates web/worker startup on migrate.sh's outcome
├── tests/
│   ├── test_set_valkey_password.sh
│   ├── test_migrate.sh
│   └── test_wait_for_migration.sh
├── templates/
│   └── terminus-unraid.xml # Unraid Docker template
├── Dockerfile              # Multi-stage build
├── LICENSE                # MIT
└── README.md              # This file
```

## Notes

- **First run** takes longer due to PostgreSQL cluster initialization.
- **APP_SETUP=true** (default) runs pending database migrations on every startup, before the web/worker
  processes start; a failed migration blocks them from starting rather than serving against a stale
  schema. Set to `false` to skip migrations entirely (e.g. when applying them out-of-band).
- Based on [Terminus](https://github.com/usetrmnl/terminus) (MIT License).
- This all-in-one image is for convenience on Unraid. For production multi-host deployments, use the upstream separate containers.

## License

MIT — see [LICENSE](LICENSE).
