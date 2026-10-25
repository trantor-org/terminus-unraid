#!/bin/bash
# deploy.sh reads UNRAID_GRAPHQL_URL from the deploy checkout's .env, where
# post-receive.sh's checkout keeps it.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

fail=0

# Mirror the host layout: the script runs from <checkout>/terminus/deploy.sh.
DEPLOY_DIR="$TMP/appdata/unraid"
mkdir -p "$DEPLOY_DIR/terminus" "$TMP/bin" "$TMP/logs"
cp "$ROOT/deploy.sh" "$DEPLOY_DIR/terminus/deploy.sh"
touch "$DEPLOY_DIR/terminus/Dockerfile"
cat >"$DEPLOY_DIR/.env" <<'EOF'
UNRAID_GRAPHQL_URL=http://unraid.test/graphql
EOF

cat >"$TMP/bin/curl" <<EOF
#!/bin/bash
echo "\$*" >>"$TMP/curl.log"
case "\$*" in
  *updateContainer*) echo '{"data":{"docker":{"updateContainer":{"id":"c1"}}}}' ;;
  *) echo '{"data":{"docker":{"containers":[{"id":"c1","names":["/terminus"]}]}}}' ;;
esac
EOF
cat >"$TMP/bin/docker" <<'EOF'
#!/bin/bash
[ "$1" = ps ] && echo "c1 terminus"
exit 0
EOF
printf '#!/bin/bash\nexit 0\n' >"$TMP/bin/sleep"
chmod +x "$TMP/bin/curl" "$TMP/bin/docker" "$TMP/bin/sleep"

env -u BASH_ENV -u UNRAID_GRAPHQL_URL -u UNRAID_API_KEY \
  PATH="$TMP/bin:$PATH" DEPLOY_LOG_DIR="$TMP/logs" \
  bash "$DEPLOY_DIR/terminus/deploy.sh" "$DEPLOY_DIR" >"$TMP/out.log" 2>&1
status=$?

if [ "$status" -eq 0 ]; then
  echo "ok: deploy.sh exits 0"
else
  echo "FAIL: deploy.sh exited $status"
  cat "$TMP/out.log"
  fail=1
fi

if grep -q "http://unraid.test/graphql" "$TMP/curl.log" 2>/dev/null; then
  echo "ok: curl received UNRAID_GRAPHQL_URL from \$DEPLOY_DIR/.env"
else
  echo "FAIL: curl never received the .env URL"
  fail=1
fi

exit "$fail"
