#!/bin/bash
set -e
cd "$(dirname "$0")"

echo "[*] Destroying environment and all student state..."
docker compose down -v

echo "[*] Redeploying from baseline..."
./deploy.sh
