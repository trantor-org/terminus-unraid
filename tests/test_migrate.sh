#!/usr/bin/env bash
# Runs scripts/migrate.sh against fake psql/bundle stubs and checks it leaves
# the right marker file behind for wait-for-migration.sh to key off.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail=0

BIN="$TMP/bin"
mkdir -p "$BIN"
export PATH="$BIN:$PATH"
export DATABASE_URL="postgres://fake/fake"
export APP_DIR="$TMP/app"
mkdir -p "$APP_DIR"

# Fake psql: readiness check passes iff $TMP/db-ready exists.
cat > "$BIN/psql" <<'EOF'
#!/usr/bin/env bash
[ -f "$TMP_DB_READY" ]
EOF
chmod +x "$BIN/psql"
export TMP_DB_READY="$TMP/db-ready"

# Fake bundle: `bundle exec hanami db migrate` exits with $TMP/bundle-exit's content (default 0).
cat > "$BIN/bundle" <<'EOF'
#!/usr/bin/env bash
exit "$(cat "$TMP_BUNDLE_EXIT" 2>/dev/null || echo 0)"
EOF
chmod +x "$BIN/bundle"
export TMP_BUNDLE_EXIT="$TMP/bundle-exit"

reset_markers() {
  rm -f "$TMP/.migrate-done" "$TMP/.migrate-failed"
}

assert_marker() {
  local label="$1" expect_done="$2" expect_failed="$3"
  local got_done=0 got_failed=0
  [ -f "$TMP/.migrate-done" ] && got_done=1
  [ -f "$TMP/.migrate-failed" ] && got_failed=1
  if [ "$got_done" != "$expect_done" ] || [ "$got_failed" != "$expect_failed" ]; then
    echo "FAIL: $label — done=$got_done failed=$got_failed (expected done=$expect_done failed=$expect_failed)"
    fail=1
  else
    echo "ok: $label"
  fi
}

# 1. Pending migration applies cleanly: DB ready, bundle succeeds.
reset_markers
touch "$TMP_DB_READY"
echo 0 > "$TMP_BUNDLE_EXIT"
DB_WAIT_TRIES=5 APP_SETUP=true "$ROOT/scripts/migrate.sh" "$TMP"
rc=$?
[ "$rc" = 0 ] || { echo "FAIL: pending migration exited $rc, expected 0"; fail=1; }
assert_marker "pending migration applied" 1 0

# 2. Already-migrated is a no-op: same as above, bundle still just exits 0.
reset_markers
DB_WAIT_TRIES=5 APP_SETUP=true "$ROOT/scripts/migrate.sh" "$TMP"
rc=$?
[ "$rc" = 0 ] || { echo "FAIL: no-op migration exited $rc, expected 0"; fail=1; }
assert_marker "already-migrated no-op" 1 0

# 3. Migration failure aborts startup: DB ready, bundle fails.
reset_markers
echo 1 > "$TMP_BUNDLE_EXIT"
DB_WAIT_TRIES=5 APP_SETUP=true "$ROOT/scripts/migrate.sh" "$TMP"
rc=$?
[ "$rc" = 1 ] || { echo "FAIL: failing migration exited $rc, expected 1"; fail=1; }
assert_marker "migration failure blocks startup" 0 1
echo 0 > "$TMP_BUNDLE_EXIT"

# 4. APP_SETUP=false skips migration entirely without touching bundle.
reset_markers
rm -f "$TMP_DB_READY"
DB_WAIT_TRIES=5 APP_SETUP=false "$ROOT/scripts/migrate.sh" "$TMP"
rc=$?
[ "$rc" = 0 ] || { echo "FAIL: APP_SETUP=false exited $rc, expected 0"; fail=1; }
assert_marker "APP_SETUP=false skips migration" 1 0

# 5. Database never becomes ready: fails loudly instead of hanging.
reset_markers
rm -f "$TMP_DB_READY"
DB_WAIT_TRIES=2 APP_SETUP=true "$ROOT/scripts/migrate.sh" "$TMP"
rc=$?
[ "$rc" = 1 ] || { echo "FAIL: unready DB exited $rc, expected 1"; fail=1; }
assert_marker "database never ready blocks startup" 0 1

exit "$fail"
