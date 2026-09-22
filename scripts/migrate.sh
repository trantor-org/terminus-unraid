#!/usr/bin/env bash
set -euo pipefail

# Waits for Postgres, then runs pending migrations once at container startup.
# Writes a marker file so wait-for-migration.sh can gate terminus-web/
# terminus-worker on the outcome instead of racing ahead on a stale schema.
# Usage: migrate.sh [marker-dir]   (default /tmp)
#   DATABASE_URL   required, passed straight to psql and to the app's migrator
#   APP_DIR        app checkout to migrate from (default /app)
#   APP_SETUP      "true" (default) runs migrations; anything else skips them
#   DB_WAIT_TRIES  readiness retry count, 1s apart (default 60)

MARKER_DIR="${1:-/tmp}"
DONE="${MARKER_DIR}/.migrate-done"
FAILED="${MARKER_DIR}/.migrate-failed"
APP_DIR="${APP_DIR:-/app}"
DB_WAIT_TRIES="${DB_WAIT_TRIES:-60}"

: "${DATABASE_URL:?DATABASE_URL is required}"

rm -f "${DONE}" "${FAILED}"

if [ "${APP_SETUP:-true}" != "true" ]; then
  echo "[migrate] APP_SETUP=${APP_SETUP:-true}, skipping migrations."
  touch "${DONE}"
  exit 0
fi

echo "[migrate] Waiting for database..."
ready=0
for _ in $(seq 1 "${DB_WAIT_TRIES}"); do
  if psql "${DATABASE_URL}" -c 'SELECT 1' >/dev/null 2>&1; then
    ready=1
    break
  fi
  sleep 1
done

if [ "${ready}" -ne 1 ]; then
  echo "[migrate] FAILED: database never became ready." >&2
  touch "${FAILED}"
  exit 1
fi

echo "[migrate] Running pending migrations..."
if (cd "${APP_DIR}" && bundle exec hanami db migrate); then
  echo "[migrate] Migrations complete."
  touch "${DONE}"
  exit 0
else
  echo "[migrate] FAILED: migration aborted, refusing to start the app." >&2
  touch "${FAILED}"
  exit 1
fi
