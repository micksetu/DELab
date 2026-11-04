#!/bin/bash
set -e
cd "$(dirname "$0")"

ATTACKER="delab-attacker"
ENDPOINT_IP="10.10.10.10"

# Stage 5 (Tier 1) adds no container of its own - it only edits the running
# manager's ossec.conf. So a genuine clean slate means rebuilding the whole
# lab (which gives a fresh manager with no active-response config) and then
# re-applying our response. We lean on Stage 4's reset, which itself chains to
# Stage 2's reset and re-adds Velociraptor - so one call rebuilds Stages 2-4.
echo "[*] Stage 5 reset: full rebuild of the lab (Stages 2-4), then re-apply"
echo "    the active response. (Slow - full Wazuh rebuild, 10-20 min. To just"
echo "    re-apply the response onto a running stack, use ./reload-response.sh.)"

echo "[*] Rebuilding the lab from baseline (Stage 2 + rule + Velociraptor)..."
(cd ../stage-4-investigation && bash reset.sh)

# The rebuild gave the endpoint new SSH host keys; clear the attacker's cached
# copy so attacks reach password auth (see deploy.sh for the full rationale).
echo "[*] Clearing any stale endpoint host key from the attacker's known_hosts..."
docker exec "$ATTACKER" sh -c "ssh-keygen -f /root/.ssh/known_hosts -R $ENDPOINT_IP >/dev/null 2>&1 || true"

echo "[*] Re-applying the Stage 5 active response..."
bash reload-response.sh

echo "[+] Stage 5 reset complete."
