#!/usr/bin/env bash
# Runs scripts/wait-for-migration.sh against marker files it did not create
# itself, checking it gates the wrapped command on migrate.sh's outcome.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail=0

reset_markers() {
  rm -f "$TMP/.migrate-done" "$TMP/.migrate-failed" "$TMP/ran"
}

# 1. Migration already done: the wrapped command runs.
reset_markers
touch "$TMP/.migrate-done"
MIGRATE_WAIT_TRIES=5 "$ROOT/scripts/wait-for-migration.sh" "$TMP" bash -c "touch '$TMP/ran'"
rc=$?
if [ "$rc" = 0 ] && [ -f "$TMP/ran" ]; then
  echo "ok: done marker lets the wrapped command run"
else
  echo "FAIL: done marker — exit=$rc ran=$([ -f "$TMP/ran" ] && echo yes || echo no)"
  fail=1
fi

# 2. Migration failed: the wrapped command must never run.
reset_markers
touch "$TMP/.migrate-failed"
MIGRATE_WAIT_TRIES=5 "$ROOT/scripts/wait-for-migration.sh" "$TMP" bash -c "touch '$TMP/ran'"
rc=$?
if [ "$rc" = 1 ] && [ ! -f "$TMP/ran" ]; then
  echo "ok: failed marker blocks the wrapped command"
else
  echo "FAIL: failed marker — exit=$rc ran=$([ -f "$TMP/ran" ] && echo yes || echo no)"
  fail=1
fi

# 3. Neither marker ever appears: times out rather than hanging or running.
reset_markers
MIGRATE_WAIT_TRIES=2 "$ROOT/scripts/wait-for-migration.sh" "$TMP" bash -c "touch '$TMP/ran'"
rc=$?
if [ "$rc" = 1 ] && [ ! -f "$TMP/ran" ]; then
  echo "ok: no marker times out without running the wrapped command"
else
  echo "FAIL: no marker — exit=$rc ran=$([ -f "$TMP/ran" ] && echo yes || echo no)"
  fail=1
fi

exit "$fail"
