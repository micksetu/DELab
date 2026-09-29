#!/bin/bash
set -e
cd "$(dirname "$0")"

PROJECT_NAME="stage2-eyes-wazuh"

echo "[*] Tearing down endpoint/attacker..."
docker rm -f stage2-endpoint stage2-attacker >/dev/null 2>&1 || true
# (stage-2-eyes_range-net is the name older versions of this lab used)
docker network rm stage2-eyes_range-net stage-2-eyes_range-net >/dev/null 2>&1 || true

if [ -d vendor/wazuh-docker/single-node ]; then
  echo "[*] Tearing down Wazuh (manager/indexer/dashboard) and its stored data..."
  (
    cd vendor/wazuh-docker/single-node
    COMPOSE_PROJECT_NAME="$PROJECT_NAME" docker compose -f docker-compose.yml down -v --remove-orphans
  ) || true
fi

# Belt and braces: remove anything still labelled with the Wazuh project
# (e.g. from an attempt whose vendor/ folder was deleted by hand). The
# manager's volumes hold agent registrations - leaving them behind is what
# causes "Duplicate agent name: endpoint01" on the next deploy.
docker ps -aq --filter "label=com.docker.compose.project=$PROJECT_NAME" | xargs docker rm -f >/dev/null 2>&1 || true
docker volume ls -q --filter "label=com.docker.compose.project=$PROJECT_NAME" | xargs docker volume rm >/dev/null 2>&1 || true
docker network ls -q --filter "label=com.docker.compose.project=$PROJECT_NAME" | xargs docker network rm >/dev/null 2>&1 || true

# vendor/ holds the cloned Wazuh stack and its generated certificates. The
# certificate generator leaves that folder read-only, so a plain rm can
# fail and stop the reset halfway. Try progressively stronger options.
echo "[*] Removing the downloaded Wazuh stack and certificates..."
rm -f .env
if [ -d vendor ]; then
  chmod -R u+w vendor 2>/dev/null || true
  rm -rf vendor 2>/dev/null || true
fi
if [ -d vendor ]; then
  # Linux: files owned by the containers' users - a root container can remove them
  docker run --rm -v "$(pwd):/work" --entrypoint rm wazuh/wazuh-certs-generator:0.0.4 -rf /work/vendor >/dev/null 2>&1 || true
fi
if [ -d vendor ]; then
  echo "    (needs your computer password to remove read-only certificate files)"
  sudo rm -rf vendor
fi

echo "[*] Redeploying from a clean baseline..."
./deploy.sh
