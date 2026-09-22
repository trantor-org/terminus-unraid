#!/usr/bin/env bash
set -euo pipefail

# Terminus All-in-One Entrypoint
# Initializes PostgreSQL, Valkey, and Terminus app on first run

POSTGRES_USER="${POSTGRES_USER:-terminus}"
POSTGRES_PASSWORD="${POSTGRES_PASSWORD}"
POSTGRES_DB="${POSTGRES_DB:-terminus}"
VALKEY_PASSWORD="${VALKEY_PASSWORD}"
APP_SECRET="${APP_SECRET}"
API_URI="${API_URI:-http://localhost:2300}"
APP_SETUP="${APP_SETUP:-true}"

export PGDATA="/var/lib/postgresql/18/docker"
export PGPASSWORD="${POSTGRES_PASSWORD}"
export PATH="/usr/lib/postgresql/18/bin:${PATH}"

# Fix ownership of PG data
if [ -d "${PGDATA}" ]; then
  chown -R postgres:postgres "${PGDATA}"
  chmod 0700 "${PGDATA}"
fi

# Fix ownership of valkey data
chown -R valkey:valkey /var/valkey 2>/dev/null || true

# Fix ownership of uploads
chown -R app:app /app/public/uploads 2>/dev/null || true

# Initialize PostgreSQL if needed
if [ ! -s "${PGDATA}/PG_VERSION" ]; then
  echo "[entrypoint] Initializing PostgreSQL database cluster..."
  mkdir -p "${PGDATA}"
  chown postgres:postgres "${PGDATA}"
  chmod 0700 "${PGDATA}"

  PWFILE=$(mktemp)
  echo "${POSTGRES_PASSWORD}" > "${PWFILE}"
  chown postgres:postgres "${PWFILE}"

  su postgres -c "initdb -D \"${PGDATA}\" -U \"${POSTGRES_USER}\" --pwfile=\"${PWFILE}\" --auth=md5"
  rm -f "${PWFILE}"

  cat > "${PGDATA}/pg_hba.conf" <<'PGHBA'
local   all             all                                     md5
host    all             all             127.0.0.1/32            md5
host    all             all             ::1/128                 md5
host    all             all             192.168.0.0/24          md5
PGHBA

  if [ "${POSTGRES_USER}" != "${POSTGRES_DB}" ]; then
    su postgres -c "createdb -U \"${POSTGRES_USER}\" \"${POSTGRES_DB}\"" || true
  fi

  echo "[entrypoint] PostgreSQL initialized."
else
  # Existing data — make sure pg_hba allows local connections
  if ! grep -q "127.0.0.1" "${PGDATA}/pg_hba.conf" 2>/dev/null; then
    cat > "${PGDATA}/pg_hba.conf" <<'PGHBA'
local   all             all                                     trust
host    all             all             127.0.0.1/32            trust
host    all             all             ::1/128                 trust
host    all             all             192.168.0.0/24          md5
PGHBA
    chown postgres:postgres "${PGDATA}/pg_hba.conf"
  fi
fi

# Set Valkey password in config
/usr/local/bin/set-valkey-password.sh /etc/valkey/valkey.conf

# Build Terminus env vars
DATABASE_URL="postgres://${POSTGRES_USER}:${POSTGRES_PASSWORD}@127.0.0.1:5432/${POSTGRES_DB}"
KEYVALUE_URL="redis://:${VALKEY_PASSWORD}@127.0.0.1:6379/0"

# Write env file for supervisord to pass to Terminus processes
cat > /etc/terminus-env <<ENVFILE
DATABASE_URL=${DATABASE_URL}
KEYVALUE_URL=${KEYVALUE_URL}
HANAMI_PORT=2300
APP_SECRET=${APP_SECRET}
API_URI=${API_URI}
APP_SETUP=${APP_SETUP}
HANAMI_ENV=production
RACK_ENV=production
PATH=/usr/local/bundle/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
ENVFILE
chmod 644 /etc/terminus-env

# Export env vars for asset compilation
export DATABASE_URL
export KEYVALUE_URL
export HANAMI_PORT=2300
export APP_SECRET
export API_URI
export APP_SETUP
export HANAMI_ENV=production
export RACK_ENV=production

# Precompile Hanami assets if not already present
if [ ! -f /app/public/assets/assets.json ]; then
  echo "[entrypoint] Compiling Hanami assets..."
  git config --global --add safe.directory /app 2>/dev/null || true
  cd /app
  bundle exec hanami assets compile 2>&1 || echo "[entrypoint] WARNING: asset compilation failed"
  chown -R app:app /app/public/assets 2>/dev/null || true
  echo "[entrypoint] Assets compiled."
fi

echo "[entrypoint] Initialization complete. Starting supervisord..."

# Clear any migration markers from a prior run before supervisord spawns
# terminus-migrate alongside terminus-web/terminus-worker: without this, a
# stale /tmp/.migrate-done from before a restart could let the app start
# before this run's migration (or its failure) is recorded.
rm -f /tmp/.migrate-done /tmp/.migrate-failed

exec "$@"
