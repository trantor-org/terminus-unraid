#!/usr/bin/env bash
set -euo pipefail

# Writes VALKEY_PASSWORD into a valkey.conf as its requirepass directive,
# replacing any earlier one so a rotated password takes effect on restart.
# Usage: set-valkey-password.sh [conf-path]   (default /etc/valkey/valkey.conf)

CONF="${1:-/etc/valkey/valkey.conf}"

if [ -n "${VALKEY_PASSWORD:-}" ]; then
  escaped=${VALKEY_PASSWORD//\\/\\\\}
  escaped=${escaped//\"/\\\"}
  { grep -v '^requirepass ' "${CONF}" || true; } > "${CONF}.new"
  echo "requirepass \"${escaped}\"" >> "${CONF}.new"
  cat "${CONF}.new" > "${CONF}"
  rm -f "${CONF}.new"
fi
