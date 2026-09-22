#!/usr/bin/env bash
set -euo pipefail

# Blocks terminus-web/terminus-worker from starting until migrate.sh (run as
# its own priority-25 supervisord program) has finished, so a container
# recreated for an image bump never serves traffic against a stale schema —
# and never starts at all if the migration failed.
# Usage: wait-for-migration.sh <marker-dir> <command...>
#   MIGRATE_WAIT_TRIES  readiness retry count, 1s apart (default 120)

MARKER_DIR="$1"; shift
DONE="${MARKER_DIR}/.migrate-done"
FAILED="${MARKER_DIR}/.migrate-failed"
WAIT_TRIES="${MIGRATE_WAIT_TRIES:-120}"

for _ in $(seq 1 "${WAIT_TRIES}"); do
  if [ -f "${FAILED}" ]; then
    echo "[wait-for-migration] Migration failed; refusing to start." >&2
    exit 1
  fi
  if [ -f "${DONE}" ]; then
    exec "$@"
  fi
  sleep 1
done

echo "[wait-for-migration] Timed out waiting for migration to finish." >&2
exit 1
