#!/bin/bash
set -e
cd "$(dirname "$0")"

# Stage 5 (Tier 1 - core): active response layered on the running delab lab.
# It owns no Wazuh, endpoint, attacker or Velociraptor - it reuses Stages 1-4
# and only adds an automated response (firewall-drop on SSH brute force).

ATTACKER="delab-attacker"
ENDPOINT_IP="10.10.10.10"

echo "[*] Stage 5 deploy starting (Tier 1: Wazuh active response)."
echo "    Ensures Stages 2-4 are up, then wires an automated firewall-drop"
echo "    response to the Stage 3 brute-force detection."
echo ""

# ---- 1. Ensure the whole delab stack (Stages 2-4) is up ------------------
# Stage 4's deploy is idempotent and chains downwards: it brings up Stage 2
# (Wazuh + endpoint + attacker) and Stage 3 (the rule), then Velociraptor.
# Cheap when everything is already running.
echo "[*] Ensuring the delab stack (Stages 2-4) is up..."
(cd ../stage-4-investigation && bash deploy.sh)

# ---- 2. Clear a stale endpoint host key from the attacker ----------------
# If the step above rebuilt/recreated the endpoint, its SSH host keys were
# regenerated. The attacker caches the old key, so SSH would abort at host-key
# verification before it ever reaches password auth - the brute force (and
# students' own attacks) would silently fail to register. Clear the old key.
echo "[*] Clearing any stale endpoint host key from the attacker's known_hosts..."
docker exec "$ATTACKER" sh -c "ssh-keygen -f /root/.ssh/known_hosts -R $ENDPOINT_IP >/dev/null 2>&1 || true"

# ---- 3. Apply the active-response configuration --------------------------
echo "[*] Applying the Stage 5 active response to the manager..."
bash reload-response.sh

echo ""
echo "[+] Stage 5 (Tier 1) deploy complete."
echo "    Wazuh dashboard : https://localhost:443  (admin / SecretPassword)"
echo "    Trigger it for real from the attacker:"
echo "      docker exec -it delab-attacker ssh student@10.10.10.10   (brute force it)"
echo "    then watch: docker exec delab-endpoint tail -f /var/ossec/logs/active-responses.log"
echo ""
echo "Next: ./validate.sh   (proves the attacker is blocked, then auto-unblocked)"
