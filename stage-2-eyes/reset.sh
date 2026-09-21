#!/bin/bash
set -e
cd "$(dirname "$0")"

echo "[*] Tearing down endpoint/attacker..."
docker compose down -v || true

if [ -d vendor/wazuh-docker/single-node ]; then
  echo "[*] Tearing down Wazuh (manager/indexer/dashboard)..."
  (
    cd vendor/wazuh-docker/single-node
    COMPOSE_PROJECT_NAME=stage2-eyes-wazuh docker compose -f docker-compose.yml down -v
  ) || true
fi

rm -rf vendor .env

# Wazuh's manager persists its agent registration state on bind-mounted
# host directories inside vendor/wazuh-docker, not in Docker-managed
# volumes - so 'down -v' above doesn't actually clear it. Removing the
# whole vendor/ directory is what makes this a real reset back to
# baseline, per Stage 1's "disposable" design principle.

echo "[*] Redeploying from a clean baseline..."
./deploy.sh
