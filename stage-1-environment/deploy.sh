#!/bin/bash
set -e
cd "$(dirname "$0")"

echo "[*] Building and starting Stage 1 environment..."
docker compose up -d --build

echo "[*] Done."
echo "    endpoint : 10.10.10.10"
echo "    attacker : 10.10.10.20"
echo ""
echo "Next: ./validate.sh to check it, ./reset.sh to wipe and rebuild from baseline."
