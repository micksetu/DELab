#!/bin/bash
set -e
cd "$(dirname "$0")"

VELO="delab-velociraptor"

echo "[*] Stage 4 reset: removes Velociraptor + its data, rebuilds the whole"
echo "    lab from baseline, then re-adds Velociraptor and the client."
echo "    (Slow - full Wazuh rebuild, same as Stage 2/3. To just re-wire"
echo "     Velociraptor without rebuilding Wazuh, re-run ./deploy.sh instead.)"

# ---- Tear down the Velociraptor server ----------------------------------
# Do this BEFORE removing .env - compose needs WAZUH_NETWORK from it to parse.
echo "[*] Tearing down Velociraptor..."
docker compose down -v --remove-orphans 2>/dev/null || true
docker rm -f "$VELO" >/dev/null 2>&1 || true

# velociraptor-data holds the server's generated config + datastore (enrolled
# clients, certs, API configs). Removing it is what makes this a genuine clean
# slate - not just a fresh container. (The client files on the endpoint are
# recreated when Stage 2's reset rebuilds the endpoint, so no cleanup here.)
echo "[*] Removing Velociraptor data (config, datastore, client/API configs)..."
rm -rf velociraptor-data .env

# ---- Rebuild the whole lab, then re-add Velociraptor ---------------------
echo "[*] Rebuilding the delab lab from baseline (Stage 2 + the Stage 3 rule)..."
(cd ../stage-2-eyes && bash reset.sh)

echo "[*] Re-adding Velociraptor and wiring the client..."
bash deploy.sh

echo "[+] Stage 4 reset complete."
