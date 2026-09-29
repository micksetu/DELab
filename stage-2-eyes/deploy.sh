#!/bin/bash
set -e
cd "$(dirname "$0")"
STAGE2_DIR="$(pwd)"

# Bump this to move to a newer Wazuh release. Pin, don't float, so every
# cohort gets the same stack. This one value pins BOTH the manager/indexer/
# dashboard (via the wazuh-docker clone) and the endpoint's agent package.
WAZUH_TAG="v4.14.7"
WAZUH_VERSION="${WAZUH_TAG#v}"

PROJECT_NAME="stage2-eyes-wazuh"
VENDOR_DIR="$STAGE2_DIR/vendor/wazuh-docker"
SINGLE_NODE="$VENDOR_DIR/single-node"
CERT_DIR="$SINGLE_NODE/config/wazuh_indexer_ssl_certs"
MANAGER="${PROJECT_NAME}-wazuh.manager-1"
INDEXER="${PROJECT_NAME}-wazuh.indexer-1"
AGENT_NAME="endpoint01"

# Run a file operation; if it's refused, retry with sudo. Only ever needed
# for the certificate files the Wazuh generator leaves read-only.
run_priv() {
  if ! "$@" 2>/dev/null; then
    echo "    (needs your computer password to fix certificate file permissions)"
    sudo "$@"
  fi
}

wazuh_compose() {
  (cd "$SINGLE_NODE" && COMPOSE_PROJECT_NAME="$PROJECT_NAME" docker compose "$@")
}

echo "[*] Stage 2 deploy starting."
echo "    This brings up Wazuh (manager + indexer + dashboard) plus the"
echo "    Stage 1 endpoint/attacker. The indexer is memory-hungry - make"
echo "    sure Docker Desktop has at least 6-8GB RAM allocated"
echo "    (Docker Desktop > Settings > Resources) before continuing."
echo ""

# ---- 0. Pre-flight: clear things that block a clean deploy ---------------
# Stage 1 and Stage 2 both use 10.10.10.0/24, and Docker refuses to create a
# second network with the same subnet. Stage 1 is disposable, so stop it.
if docker ps -a --format '{{.Names}}' | grep -Eqx 'stage1-(endpoint|attacker)'; then
  echo "[*] Stage 1 is still running and uses the same 10.10.10.0/24 range - stopping it..."
  docker compose -f ../stage-1-environment/docker-compose.yml down -v --remove-orphans
fi

# Leftover endpoint/attacker containers (and their range network) from an
# earlier attempt - recreated below anyway.
docker rm -f stage2-endpoint stage2-attacker >/dev/null 2>&1 || true
# (stage-2-eyes_range-net is the name older versions of this lab used)
docker network rm stage2-eyes_range-net stage-2-eyes_range-net >/dev/null 2>&1 || true

# Anything else still holding 10.10.10.0/24 will make the endpoint/attacker
# fail with an address-pool error.
for net in $(docker network ls -q); do
  name=$(docker network inspect -f '{{.Name}}' "$net")
  if docker network inspect -f '{{range .IPAM.Config}}{{.Subnet}} {{end}}' "$net" | grep -q '10\.10\.10\.0/24'; then
    echo "    FAIL: Docker network '$name' already uses 10.10.10.0/24."
    echo "    Stop whatever uses it, run 'docker network rm $name',"
    echo "    then run ./deploy.sh again."
    exit 1
  fi
done

# ---- 1. Fetch the official Wazuh docker stack, pinned to a known tag ----
FRESH_CLONE=0
if [ ! -d "$VENDOR_DIR" ]; then
  echo "[*] Cloning wazuh-docker ($WAZUH_TAG)..."
  git clone --branch "$WAZUH_TAG" --depth 1 https://github.com/wazuh/wazuh-docker.git "$VENDOR_DIR"
  FRESH_CLONE=1
else
  echo "[*] wazuh-docker already present at vendor/wazuh-docker, skipping clone."
fi

# A fresh clone means a fresh start: remove any Wazuh containers/volumes an
# earlier attempt left under the same project name. Those volumes hold the
# manager's old agent registrations.
if [ "$FRESH_CLONE" -eq 1 ]; then
  echo "[*] Removing leftovers from any earlier Wazuh attempt..."
  wazuh_compose -f docker-compose.yml down -v --remove-orphans >/dev/null 2>&1 || true
fi

# The indexer's host port (9200) frequently collides with a local
# Elasticsearch/OpenSearch install or a leftover container from an earlier
# attempt. We don't need it reachable from the host - the manager and
# dashboard talk to it over the Docker network - so remap it out of the way.
INDEXER_COMPOSE="$SINGLE_NODE/docker-compose.yml"
if grep -q '"9200:9200"' "$INDEXER_COMPOSE" 2>/dev/null; then
  echo "[*] Remapping indexer's host port 9200 -> 9400 to avoid collisions..."
  sed -i.bak 's/"9200:9200"/"9400:9200"/' "$INDEXER_COMPOSE"
fi

# ---- 2. Certificates -------------------------------------------------------
# Generate once. Re-running the generator over existing (read-only) certs
# only produces "cp: cannot create regular file ... Permission denied" noise.
if [ ! -f "$CERT_DIR/wazuh.indexer.pem" ]; then
  echo "[*] Generating Wazuh SSL certificates..."
  echo "    (on macOS, a few 'Permission denied' lines here are expected - fixed below)"
  wazuh_compose -f generate-indexer-certs.yml run --rm generator || true
else
  echo "[*] Wazuh certificates already generated, skipping."
fi

# The generator makes its output folder read-only BEFORE copying the CA into
# root-ca-manager.pem/.key. On Linux that works because root ignores the
# folder permission; on Docker Desktop for macOS it doesn't, so those two
# files are never created, Docker creates *folders* in their place when the
# manager starts, and the deploy fails. Create them here instead.
for f in root-ca-manager.pem root-ca-manager.key; do
  if [ -d "$CERT_DIR/$f" ]; then run_priv rm -rf "$CERT_DIR/$f"; fi
done
if [ ! -f "$CERT_DIR/root-ca-manager.pem" ] || [ ! -f "$CERT_DIR/root-ca-manager.key" ]; then
  echo "[*] Creating missing manager CA files..."
  run_priv chmod u+rwx "$CERT_DIR"
  run_priv cp "$CERT_DIR/root-ca.pem" "$CERT_DIR/root-ca-manager.pem"
  run_priv cp "$CERT_DIR/root-ca.key" "$CERT_DIR/root-ca-manager.key"
fi

# On macOS the generator's chown to the containers' user IDs has no effect,
# so the indexer/dashboard can't read their own keys. Make the certs
# readable. (World-readable keys: fine for this disposable local lab only.)
if [ "$(uname -s)" = "Darwin" ]; then
  echo "[*] Fixing Wazuh certificate permissions for Docker Desktop on macOS..."
  run_priv chmod 755 "$CERT_DIR"
  run_priv chmod 444 "$CERT_DIR"/*
fi

# Never let Docker start the stack with a cert missing - it would silently
# create a folder in its place and fail with a confusing mount error.
for f in root-ca.pem root-ca-manager.pem wazuh.manager.pem wazuh.manager-key.pem \
         wazuh.indexer.pem wazuh.indexer-key.pem admin.pem admin-key.pem \
         wazuh.dashboard.pem wazuh.dashboard-key.pem; do
  if [ ! -f "$CERT_DIR/$f" ]; then
    echo "    FAIL: certificate $f was not created."
    echo "    Run ./reset.sh to start again from a clean baseline."
    exit 1
  fi
done

# ---- 3. Bring up the Wazuh stack under its own compose project ----------
# No enrollment password - see Stage 2 README's "How agent enrollment
# works" section for why.
echo "[*] Starting Wazuh manager, indexer, dashboard..."
wazuh_compose -f docker-compose.yml up -d

echo "[*] Waiting for the Wazuh indexer's cluster to come up (can take a couple of minutes)..."
echo "    (this checks the indexer's own logs, since its image has no Docker healthcheck)"
for i in $(seq 1 30); do
  if docker logs "$INDEXER" 2>&1 | grep -q "Cluster health status changed"; then
    echo "    indexer cluster is up"
    break
  fi
  echo "    still starting... (${i}/30)"
  sleep 10
done

echo "[*] Waiting for the Wazuh manager to accept agents..."
for i in $(seq 1 30); do
  if docker exec "$MANAGER" /var/ossec/bin/wazuh-control status 2>/dev/null | grep -q "wazuh-authd is running"; then
    echo "    manager is up"
    break
  fi
  echo "    still starting... (${i}/30)"
  sleep 10
done

# Every deploy creates a brand-new endpoint, which enrolls from scratch. If
# the manager still holds a registration under the same name from an
# earlier endpoint, it rejects the new one ("Duplicate agent name").
OLD_IDS=$(docker exec "$MANAGER" /var/ossec/bin/agent_control -l 2>/dev/null \
  | grep "Name: ${AGENT_NAME}," | sed -E 's/.*ID: ([0-9]+),.*/\1/' || true)
for id in $OLD_IDS; do
  echo "[*] Removing old '${AGENT_NAME}' registration (agent ID $id) from the manager..."
  docker exec "$MANAGER" /var/ossec/bin/manage_agents -r "$id" >/dev/null
done

# ---- 4. Attach our endpoint/attacker to the Wazuh stack's network --------
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
WAZUH_VERSION=$WAZUH_VERSION
EOF

# --force-recreate: always a fresh endpoint, so it always enrolls cleanly
# against the registration state we just tidied up above.
echo "[*] Building and starting the endpoint and attacker..."
docker compose up -d --build --force-recreate

echo ""
echo "[+] Stage 2 deploy complete."
echo "    Wazuh dashboard : https://localhost:443  (admin / SecretPassword - the"
echo "                      wazuh-docker single-node default, teaching use only)"
echo "    endpoint        : 10.10.10.10   attacker : 10.10.10.20"
echo ""
echo "Next: ./validate.sh (the agent can take up to a minute to show connected),"
echo "      ./reset.sh to wipe everything (including Wazuh) and rebuild from baseline."
