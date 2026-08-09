---
title: "TRMNL E-ink Display"
summary: "Physical e-ink display (1872×1404) polling the Terminus API for screen content"
tags: [unraid, trmnl, services, cronicle, screen]
template: "subsystem"
ip-addresses:
  terminus: 192.168.0.44:2300
---

# TRMNL E-ink Display

Physical e-ink display device that polls the Terminus server API for screen
content.

## Location

| Item | Value |
|------|-------|
| Screen ID | 1 |
| Resolution | 1872×1404 |
| Terminus API | <http://[ip-address: terminus]> |

## Screen Generation

The main screen fetches Google Calendar, Sonarr/Radarr, and wttr.in data,
renders HTML, and pushes it to the Terminus API. The TRMNL device polls the
API to retrieve the rendered screen.

Screen updates are pushed on a schedule via Cronicle. CMD must NOT include
`--print-html` — that flag sends HTML to stdout instead of pushing to the
display.

### Local Development

A dev server (`serve.py`) renders the screen locally for testing. It is
dev-only — it does not push to the Terminus API. Use `trmnl_main_screen.py`
for production pushes.

## Troubleshooting

### Frozen / Stale Screen

The e-ink display holds its last image without power, so a frozen screen
looks normal even when the firmware is completely hung. Signs the device is
frozen:

- Screen content is hours old (check `synced_at` in the DB)
- Buttons on the back do nothing (short press doesn't refresh)
- Device MAC not in router ARP table

**Diagnose server-side first** — the issue is usually the device, not the
server:

```sh
# Check if Cronicle is pushing screens successfully
bin/cronicle/api.sh history emqeiddoi09

# Check if Terminus is serving the latest image
ssh unraid "curl -sI http://192.168.0.44:2300/uploads/<latest-hash>.png"

# Check device sync state and battery
ssh unraid "docker exec terminus psql -U terminus -d terminus -c \
  'SELECT id, label, synced_at, battery_charge, wifi_signal FROM device;'"
```

If the server side is healthy (Cronicle OK, Terminus serving image, API
responds to a simulated poll), the device firmware is hung.

**Reset procedure** — the TRMNL has a single button on the back with
different hold durations:

| Hold duration | Action |
|---------------|--------|
| Short press | Refresh display |
| 5-7 seconds | WiFi reset / captive portal |
| 10 seconds | Factory reset (screen shows "Resetting", release then press once to confirm) |
| 16-18 seconds | Soft reset (reboot) |

For a frozen device, **hold the back button for 16-18 seconds** (soft
reset). If that doesn't work, try 10 seconds (factory reset). If the
battery is very low, plug into USB-C first — a dead battery can prevent
reset even when the screen still shows an image.

### Known Cause: Terminus Downtime

If the Terminus server is briefly unreachable (container restart, network
blip), the device may get "connection refused" errors and enter a hung state
that it doesn't recover from automatically. A manual soft reset is required.

## Deployment

Screen code deploys via the deployment pipeline. Push to the `deploy` remote
and the post-receive hook runs `trmnl/deploy.sh`, which rebuilds
and pushes the screen.
