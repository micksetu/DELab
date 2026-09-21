#!/bin/bash
set -e
cd "$(dirname "$0")"
STAGE2_DIR="$(pwd)"

# Bump this to move to a newer Wazuh release. Pin, don't float, so every
# cohort gets the same stack.
WAZUH_TAG="v4.14.7"

PROJECT_NAME="stage2-eyes-wazuh"
VENDOR_DIR="$STAGE2_DIR/vendor/wazuh-docker"

echo "[*] Stage 2 deploy starting."
echo "    This brings up Wazuh (manager + indexer + dashboard) plus the"
echo "    Stage 1 endpoint/attacker. The indexer is memory-hungry - make"
echo "    sure Docker Desktop has at least 6-8GB RAM allocated"
echo "    (Docker Desktop > Settings > Resources) before continuing."
echo ""

# ---- 1. Fetch the official Wazuh docker stack, pinned to a known tag ----
if [ ! -d "$VENDOR_DIR" ]; then
  echo "[*] Cloning wazuh-docker ($WAZUH_TAG)..."
  git clone --branch "$WAZUH_TAG" --depth 1 https://github.com/wazuh/wazuh-docker.git "$VENDOR_DIR"
else
  echo "[*] wazuh-docker already present at vendor/wazuh-docker, skipping clone."
fi

# The indexer's host port (9200) frequently collides with a local
# Elasticsearch/OpenSearch install or a leftover container from an earlier
# attempt. We don't need it reachable from the host - the manager and
# dashboard talk to it over the Docker network - so remap it out of the way.
INDEXER_COMPOSE="$VENDOR_DIR/single-node/docker-compose.yml"
if grep -q '"9200:9200"' "$INDEXER_COMPOSE" 2>/dev/null; then
  echo "[*] Remapping indexer's host port 9200 -> 9400 to avoid collisions..."
  sed -i.bak 's/"9200:9200"/"9400:9200"/' "$INDEXER_COMPOSE"
fi

# ---- 2. Bring up the Wazuh stack under its own compose project ----------
# No enrollment password - see Stage 2 README's "How agent enrollment
# works" section for why. Manager runs with wazuh-authd's own default
# (no password required), and the agent is configured to match.
echo "[*] Generating Wazuh indexer SSL certificates (first run only, safe to re-run)..."
(
  cd "$VENDOR_DIR/single-node"
  COMPOSE_PROJECT_NAME="$PROJECT_NAME" docker compose -f generate-indexer-certs.yml run --rm generator
)

echo "[*] Starting Wazuh manager, indexer, dashboard..."
(
  cd "$VENDOR_DIR/single-node"
  COMPOSE_PROJECT_NAME="$PROJECT_NAME" docker compose -f docker-compose.yml up -d
)

echo "[*] Waiting for the Wazuh indexer's cluster to come up (can take a couple of minutes)..."
echo "    (this checks the indexer's own logs, since its image has no Docker healthcheck)"
for i in $(seq 1 30); do
  if docker logs "${PROJECT_NAME}-wazuh.indexer-1" 2>&1 | grep -q "Cluster health status changed"; then
    echo "    indexer cluster is up"
    break
  fi
  echo "    still starting... (${i}/30)"
  sleep 10
done

# ---- 3. Attach our endpoint/attacker to the Wazuh stack's network --------
echo "[*] Discovering the Wazuh network..."
WAZUH_NETWORK=$(docker network ls --filter "label=com.docker.compose.project=$PROJECT_NAME" --format '{{.Name}}' | head -n1)
if [ -z "$WAZUH_NETWORK" ]; then
  echo "    FAIL: could not find a Docker network for project $PROJECT_NAME"
  echo "    Run 'docker network ls' and check the Wazuh containers started."
  exit 1
fi
echo "    found: $WAZUH_NETWORK"

cat > "$STAGE2_DIR/.env" <<EOF
WAZUH_NETWORK=$WAZUH_NETWORK
EOF

echo "[*] Building and starting the endpoint and attacker..."
docker compose up -d --build

echo ""
echo "[+] Stage 2 deploy complete."
echo "    Wazuh dashboard : https://localhost:443  (admin / SecretPassword - the"
echo "                      wazuh-docker single-node default, teaching use only)"
echo "    endpoint        : 10.10.10.10   attacker : 10.10.10.20"
echo ""
echo "Next: ./validate.sh (the agent can take up to a minute to show connected),"
echo "      ./reset.sh to wipe everything (including Wazuh) and rebuild from baseline."
