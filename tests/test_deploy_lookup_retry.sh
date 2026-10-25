#!/bin/bash
# deploy.sh retries the container lookup while the Unraid API lags behind the
# template rebuild, and logs the response when it gives up.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

fail=0

DEPLOY_DIR="$TMP/appdata/unraid"
mkdir -p "$DEPLOY_DIR/terminus" "$TMP/bin" "$TMP/logs"
cp "$ROOT/deploy.sh" "$DEPLOY_DIR/terminus/deploy.sh"
touch "$DEPLOY_DIR/terminus/Dockerfile"
echo "UNRAID_GRAPHQL_URL=http://unraid.test/graphql" >"$DEPLOY_DIR/.env"

cat >"$TMP/bin/curl" <<EOF
#!/bin/bash
case "\$*" in
  *updateContainer*) echo '{"data":{"docker":{"updateContainer":{"id":"c1"}}}}'; exit 0 ;;
esac
n=\$(cat "$TMP/lookups" 2>/dev/null || echo 0)
echo \$((n + 1)) >"$TMP/lookups"
if [ "\$n" -lt "\$FAIL_LOOKUPS" ]; then
  echo '{"errors":[{"message":"container starting"}]}'
else
  echo '{"data":{"docker":{"containers":[{"id":"c1","names":["/terminus"]}]}}}'
fi
EOF
cat >"$TMP/bin/docker" <<'EOF'
#!/bin/bash
[ "$1" = ps ] && echo "c1 terminus"
exit 0
EOF
printf '#!/bin/bash\nexit 0\n' >"$TMP/bin/sleep"
chmod +x "$TMP/bin/curl" "$TMP/bin/docker" "$TMP/bin/sleep"

run_deploy() {
  rm -f "$TMP/lookups"
  env -u BASH_ENV UNRAID_API_KEY=k FAIL_LOOKUPS="$1" PATH="$TMP/bin:$PATH" DEPLOY_LOG_DIR="$TMP/logs" \
    bash "$DEPLOY_DIR/terminus/deploy.sh" "$DEPLOY_DIR" >"$TMP/out.log" 2>&1
}

if run_deploy 2; then
  echo "ok: a lookup that fails twice is retried"
else
  echo "FAIL: deploy.sh gave up after two failed lookups"
  cat "$TMP/out.log"
  fail=1
fi

run_deploy 99
status=$?
if [ "$status" -ne 0 ] && grep -q "Lookup attempt 1 failed.*container starting" "$TMP/out.log" &&
  grep -q "Could not find terminus container" "$TMP/out.log"; then
  echo "ok: a lookup that never succeeds logs the response and the ERROR"
else
  echo "FAIL: exit $status without the logged response and ERROR"
  cat "$TMP/out.log"
  fail=1
fi

exit "$fail"
