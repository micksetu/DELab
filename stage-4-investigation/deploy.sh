#!/bin/bash
set -e
cd "$(dirname "$0")"
STAGE4_DIR="$(pwd)"

# Bump to move to a newer Velociraptor release. Pin, don't float, so every
# cohort gets the same stack. 0.77.3 is the current stable (patches CVEs).
VELO_IMAGE="ghcr.io/velocidex/velociraptor-server:0.77.3"
VELOCIRAPTOR_ADMIN_PASSWORD="VelociraptorLab123!"

WAZUH_PROJECT="delab-wazuh"
VELO="delab-velociraptor"
ENDPOINT="delab-endpoint"

echo "[*] Stage 4 deploy starting."
echo "    Adds Velociraptor (investigation) onto the running delab lab and"
echo "    wires a client onto the endpoint. It does NOT run its own Wazuh -"
echo "    it reuses the Stage 2/3 stack."
echo ""

# ---- 1. Make sure the delab stack (Stages 2-3) is up and current ---------
# Stage 3's deploy is idempotent: it brings the Stage 2 stack up if it's
# down, and always (re)loads the Stage 3 rule. Cheap when already running.
echo "[*] Ensuring the delab stack (Stages 2 + 3) is up..."
(cd ../stage-3-detections && bash deploy.sh)

# The Velociraptor client auto-start lives in the Stage 2 endpoint entrypoint
# (so the client survives an endpoint restart). If the running endpoint image
# predates that change, rebuild it via Stage 2's deploy.
if ! docker exec "$ENDPOINT" grep -q "starting Velociraptor client" /entrypoint.sh 2>/dev/null; then
  echo "[*] Endpoint image predates Stage 4 client support - rebuilding it..."
  (cd ../stage-2-eyes && bash deploy.sh)
fi

# ---- 2. Start the Velociraptor server on the shared Wazuh network --------
echo "[*] Discovering the shared Wazuh network..."
WAZUH_NETWORK=$(docker network ls --filter "label=com.docker.compose.project=$WAZUH_PROJECT" --format '{{.Name}}' | head -n1)
if [ -z "$WAZUH_NETWORK" ]; then
  echo "    FAIL: couldn't find the '$WAZUH_PROJECT' network. Is the delab stack up?"
  echo "    Try: cd ../stage-2-eyes && ./deploy.sh"
  exit 1
fi
echo "    found: $WAZUH_NETWORK"

# Warn early if the GUI port is already taken, rather than a cryptic bind error.
if docker ps --format '{{.Ports}}' | grep -q ':8889->'; then
  echo "    NOTE: something is already publishing host port 8889 - if the"
  echo "          server fails to start, free that port or remap 8889 in"
  echo "          docker-compose.yml."
fi

cat > "$STAGE4_DIR/.env" <<EOF
WAZUH_NETWORK=$WAZUH_NETWORK
VELOCIRAPTOR_ADMIN_PASSWORD=$VELOCIRAPTOR_ADMIN_PASSWORD
EOF

echo "[*] Starting the Velociraptor server ($VELO_IMAGE)..."
docker compose up -d

# ---- 3. Wait for the server to generate its config -----------------------
# First run generates server.config.yaml (self-signed certs, admin user) and
# builds client deployment packages - that can take a minute or two.
echo "[*] Waiting for the Velociraptor server to initialise..."
SERVER_CONF=/etc/velociraptor/server.config.yaml
for i in $(seq 1 36); do
  if docker exec "$VELO" test -f "$SERVER_CONF" 2>/dev/null; then
    echo "    server config present"
    break
  fi
  echo "    still starting... ($i/36)"
  sleep 5
done
if ! docker exec "$VELO" test -f "$SERVER_CONF" 2>/dev/null; then
  echo "    FAIL: the server never generated its config. Check: docker logs $VELO"
  exit 1
fi

# ---- 4. Extract a client config and wire the endpoint up as a client -----
# Velociraptor's server and client are the same binary - "config client"
# emits a ready-to-use client.config.yaml from the running server's config.
mkdir -p "$STAGE4_DIR/velociraptor-data"
echo "[*] Extracting a client config from the server..."
docker exec "$VELO" velociraptor --config "$SERVER_CONF" config client \
  > "$STAGE4_DIR/velociraptor-data/client.config.yaml"

# Point the client at the server by its network alias, deterministically -
# whatever hostname the server baked into the config, the endpoint reaches it
# as 'velociraptor' on the shared network.
sed -i.bak -E 's#https?://[^:/]+:8000/#https://velociraptor:8000/#g' \
  "$STAGE4_DIR/velociraptor-data/client.config.yaml"
rm -f "$STAGE4_DIR/velociraptor-data/client.config.yaml.bak"

# Copy the server's OWN binary onto the endpoint (guarantees the architecture
# matches the host - the image layout isn't documented, so find it rather
# than guess a path).
VELO_BINARY=$(docker exec "$VELO" sh -c 'command -v velociraptor')
echo "    server binary at: $VELO_BINARY"

echo "[*] Copying the Velociraptor binary + client config onto the endpoint..."
docker exec "$ENDPOINT" mkdir -p /opt/velociraptor
docker cp "$VELO:$VELO_BINARY" "$STAGE4_DIR/velociraptor-data/velociraptor-binary"
docker cp "$STAGE4_DIR/velociraptor-data/velociraptor-binary" "$ENDPOINT:/opt/velociraptor/velociraptor"
docker exec "$ENDPOINT" chmod +x /opt/velociraptor/velociraptor
docker cp "$STAGE4_DIR/velociraptor-data/client.config.yaml" "$ENDPOINT:/opt/velociraptor/client.config.yaml"

# Restart the endpoint so its entrypoint launches the client. We do NOT use
# `docker exec -d` here: detached-exec processes aren't reliably kept alive,
# and the endpoint's own entrypoint (the Stage 2 guarded block) is the proper
# supervisor - it starts the client as a child of PID 1 and logs it. This is
# also exactly how the client comes back after any endpoint restart.
echo "[*] Restarting the endpoint so it launches the Velociraptor client..."
docker restart "$ENDPOINT" >/dev/null

# Enrolment has to be checked against the LIVE server via its API - a plain
# `query --config server.config.yaml` runs in a throwaway context and never
# sees enrolled clients. Issue an API cert under the existing 'admin' user
# (already an administrator, so no ACL grant needed) and query with it.
API_CONF=/etc/velociraptor/admin.api.yaml
docker exec "$VELO" sh -c "test -f $API_CONF || velociraptor --config $SERVER_CONF config api_client --name admin --role administrator $API_CONF >/dev/null 2>&1"

echo "[*] Waiting for the Velociraptor client to enrol with the server..."
ENROLLED=no
for i in $(seq 1 24); do   # up to ~2 min
  if docker exec "$VELO" velociraptor --api_config "$API_CONF" \
       query --format jsonl "SELECT os_info.hostname AS host FROM clients()" 2>/dev/null \
       | grep -qi "endpoint01"; then
    ENROLLED=yes
    break
  fi
  echo "    not enrolled yet... ($i/24)"
  sleep 5
done

echo ""
if [ "$ENROLLED" = yes ]; then
  echo "[+] Stage 4 deploy complete - the Velociraptor client is enrolled."
else
  echo "[!] Stage 4 deploy finished, but the client has not enrolled yet."
  echo "    It can take a little longer on first run. Re-run ./validate.sh in a"
  echo "    minute. If it stays unenrolled, check the client's log:"
  echo "        docker exec $ENDPOINT tail -30 /var/log/velociraptor-client.log"
fi
echo ""
echo "    Wazuh dashboard        : https://localhost:443   (admin / SecretPassword)"
echo "    Velociraptor dashboard : https://localhost:8889  (admin / $VELOCIRAPTOR_ADMIN_PASSWORD)"
echo "    endpoint : 10.10.10.10    attacker : 10.10.10.20"
echo ""
echo "The client can take up to a minute to show as connected. In the"
echo "Velociraptor GUI, search for 'endpoint01'."
echo "Next: ./validate.sh, or ./reset.sh to wipe Velociraptor and rebuild."
