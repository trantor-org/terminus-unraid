#!/usr/bin/env bash
# Runs scripts/set-valkey-password.sh against a copy of config/valkey.conf and
# checks the password Valkey would read back matches the one given.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail=0

# Prints the requirepass value as valkey parses it: quoted string, \\ and \" unescaped.
effective_password() {
  local line
  line=$(grep '^requirepass ' "$1" | tail -n1) || return 1
  line=${line#requirepass \"}
  line=${line%\"}
  line=${line//\\\"/\"}
  printf '%s' "${line//\\\\/\\}"
}

check() {
  local password="$1" conf="$TMP/valkey.conf"
  cp "$ROOT/config/valkey.conf" "$conf"
  VALKEY_PASSWORD="$password" "$ROOT/scripts/set-valkey-password.sh" "$conf"
  local got
  got=$(effective_password "$conf") || got="<no requirepass>"
  if [ "$got" != "$password" ]; then
    echo "FAIL: password '$password' became '$got'"
    fail=1
  else
    echo "ok: '$password'"
  fi
  if [ "$(grep -c '^requirepass ' "$conf")" != 1 ]; then
    echo "FAIL: expected exactly one requirepass for '$password'"
    fail=1
  fi
}

check 'plainSecret123'
check 'a&b'
check 'a/b'
check 'a\b'
check 'a"b'

# Re-running (container restart) must replace the directive, not stack a second one.
cp "$ROOT/config/valkey.conf" "$TMP/valkey.conf"
VALKEY_PASSWORD=first "$ROOT/scripts/set-valkey-password.sh" "$TMP/valkey.conf"
VALKEY_PASSWORD=second "$ROOT/scripts/set-valkey-password.sh" "$TMP/valkey.conf"
if [ "$(effective_password "$TMP/valkey.conf")" != second ]; then
  echo "FAIL: restart with a rotated password kept the old one"
  fail=1
fi

exit "$fail"
