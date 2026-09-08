#!/bin/bash
# Deploy: Terminus container image
# Triggered by: post-receive hook when terminus/ changes
# What it does: Builds the Terminus Docker image on Unraid from the
#   NFS-mounted repo, then updates the container via Unraid GraphQL API.
#
# Logs: /mnt/user/appdata/deploy-logs/terminus-image-<timestamp>.log

set -euo pipefail

DEPLOY_DIR="${1:-/mnt/user/appdata/unraid-sync}"
LOG_DIR="/mnt/user/appdata/deploy-logs"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
LOG_FILE="$LOG_DIR/terminus-image-$TIMESTAMP.log"

mkdir -p "$LOG_DIR"

# Load infrastructure env vars from .envrc
_WORKSPACE="$(cd "$(dirname "$0")/../.." && pwd)"
if [ -f "$_WORKSPACE/.env" ]; then
  source "$_WORKSPACE/.env"
fi

# Source secrets for Unraid API key
SECRETS_DIR="/mnt/user/appdata/cronicle-trmnl-secrets"
if [ -f "$SECRETS_DIR/terminus.env" ]; then
  source "$SECRETS_DIR/terminus.env"
fi

# Also try the repo secrets
if [ -z "${UNRAID_API_KEY:-}" ]; then  # may not be set yet before sourcing secrets
  REPO_SECRETS="$DEPLOY_DIR/secrets.env"
  if [ -f "$REPO_SECRETS" ]; then
    source "$REPO_SECRETS"
  fi
fi

echo "[$(date -Iseconds)] Terminus image deploy started" | tee "$LOG_FILE"

BUILD_CTX="$DEPLOY_DIR/terminus"
IMAGE_TAG="ghcr.io/adinballew/terminus-unraid:local"

if [ ! -f "$BUILD_CTX/Dockerfile" ]; then
  echo "ERROR: Dockerfile not found at $BUILD_CTX" | tee -a "$LOG_FILE"
  exit 1
fi

# Build the image
echo "  Building image from $BUILD_CTX..." | tee -a "$LOG_FILE"
if docker build -t "$IMAGE_TAG" "$BUILD_CTX" >>"$LOG_FILE" 2>&1; then
  echo "  Image built: $IMAGE_TAG" | tee -a "$LOG_FILE"
else
  EXIT_CODE=$?
  echo "ERROR: Image build failed (exit $EXIT_CODE)" | tee -a "$LOG_FILE"
  exit $EXIT_CODE
fi

# Find the Terminus container ID via Unraid GraphQL API
echo "  Fetching container ID from Unraid API..." | tee -a "$LOG_FILE"
CONTAINER_JSON=$(curl -s -X POST ${UNRAID_GRAPHQL_URL} \
  -H "Content-Type: application/json" \
  -H "x-api-key: ***" \
  -d '{"query":"{ docker { containers { id names } } }"}')

CONTAINER_ID=$(echo "$CONTAINER_JSON" | python3 -c "
import sys, json
data = json.load(sys.stdin)
for c in data['data']['docker']['containers']:
    if '/terminus' in c['names']:
        print(c['id'])
        break
" 2>/dev/null)

if [ -z "$CONTAINER_ID" ]; then
  echo "ERROR: Could not find terminus container in Unraid API" | tee -a "$LOG_FILE"
  exit 1
fi

echo "  Container ID: $CONTAINER_ID" | tee -a "$LOG_FILE"

# Update the container (pulls nothing since we built locally, recreates from template)
echo "  Updating container via Unraid API..." | tee -a "$LOG_FILE"
UPDATE_RESULT=$(curl -s -X POST ${UNRAID_GRAPHQL_URL} \
  -H "Content-Type: application/json" \
  -H "x-api-key: ***" \
  -d "{\"query\":\"mutation { docker { updateContainer(id: \\\"$CONTAINER_ID\\\") { id names state } } }\"}")

echo "  API response: $UPDATE_RESULT" | tee -a "$LOG_FILE"

# Check if the update succeeded
if echo "$UPDATE_RESULT" | python3 -c "
import sys, json
data = json.load(sys.stdin)
if 'errors' in data:
    print('ERROR: ' + str(data['errors']))
    sys.exit(1)
print('OK: ' + str(data.get('data', {}).get('docker', {}).get('updateContainer', {})))
" 2>&1 | tee -a "$LOG_FILE"; then
  # Wait for container to be healthy
  echo "  Waiting for container to start..." | tee -a "$LOG_FILE"
  sleep 10

  # Verify container is running
  if docker ps --filter name=terminus --filter status=running | grep -q terminus; then
    echo "  Container is running" | tee -a "$LOG_FILE"

    # Verify the font is now in the container
    if docker exec terminus ls /usr/share/fonts/truetype/noto/NotoEmoji-Regular.ttf 2>/dev/null; then
      echo "  NotoEmoji font confirmed in container" | tee -a "$LOG_FILE"
    else
      echo "  WARN: NotoEmoji font not found in container" | tee -a "$LOG_FILE"
    fi

    echo "[$(date -Iseconds)] Terminus image deploy SUCCESS" | tee -a "$LOG_FILE"
    exit 0
  else
    echo "ERROR: Container is not running after update" | tee -a "$LOG_FILE"
    exit 1
  fi
else
  echo "[$(date -Iseconds)] Terminus image deploy FAILED" | tee -a "$LOG_FILE"
  exit 1
fi