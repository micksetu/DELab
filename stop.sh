#!/bin/bash
# Stop the DELab lab when you're done for now.
#
# This STOPS the lab's containers (freeing the RAM and CPU the Wazuh indexer
# in particular holds), but does NOT delete them - so ./start.sh brings the
# lab back in seconds, instead of the 10-20 minute rebuild a fresh deploy
# costs. Use ./reset.sh (in a stage folder) only when you actually want a
# clean baseline rebuilt from scratch.
#
# Scoped to the lab's own containers (named delab-*): it will not touch any
# other Docker containers you have running. Run it from anywhere.
#
# Note: Stage 1, if you ever run it on its own, is a separate set of
# containers (stage1-*) with its own `docker compose` lifecycle - this script
# deliberately leaves it alone.
set -u

RUNNING=$(docker ps -q --filter name=delab)
if [ -z "$RUNNING" ]; then
  echo "[*] No running delab-* containers - the lab is already stopped."
  exit 0
fi

echo "[*] Stopping the DELab lab (delab-* containers)..."
docker ps -q --filter name=delab | xargs -r docker stop
echo "[+] Stopped. Resume with ./start.sh (no rebuild needed)."
