#!/bin/bash
# Resume the DELab lab after ./stop.sh - without rebuilding.
#
# Starts the lab's existing (stopped) containers. The Wazuh indexer is started
# first and given a moment, so the dashboard doesn't race it on resume (the
# same ordering reason as deploy.sh). Scoped to delab-* containers only.
#
# If no delab-* containers exist yet, there's nothing to resume - run a
# stage's ./deploy.sh to create the lab first.
set -u

EXISTING=$(docker ps -aq --filter name=delab)
if [ -z "$EXISTING" ]; then
  echo "[*] No delab-* containers exist yet - nothing to resume."
  echo "    Create the lab first: cd stage-2-eyes && ./deploy.sh"
  exit 0
fi

echo "[*] Resuming the DELab lab (no rebuild)..."

# Indexer first, then the rest. Starting an already-running container is a
# harmless no-op, so it's fine that the second start also covers the indexer.
docker ps -aq --filter name=delab-wazuh-wazuh.indexer | xargs -r docker start >/dev/null
sleep 10
docker ps -aq --filter name=delab | xargs -r docker start >/dev/null

echo "[+] Lab started. The Wazuh dashboard (https://localhost:443) can take a"
echo "    minute to be ready. Confirm the pipeline with:"
echo "        cd stage-3-detections && ./validate.sh"
