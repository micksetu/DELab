#!/bin/bash
set -e
cd "$(dirname "$0")"

MANAGER="delab-wazuh-wazuh.manager-1"

echo "[*] Stage 3 deploy starting."
echo "    Stage 3 adds a custom detection rule onto the Stage 2 stack - it"
echo "    does NOT run its own Wazuh. So first we make sure Stage 2 is up."
echo ""

# ---- 1. Make sure the Stage 2 stack is running ---------------------------
# If the manager container is up, the lab is already running and we just
# load the rule onto it (seconds). If not, run Stage 2's deploy, which
# brings up Wazuh + endpoint + attacker (the slow 10-20 min first run).
if [ "$(docker inspect -f '{{.State.Running}}' "$MANAGER" 2>/dev/null)" = "true" ]; then
  echo "[*] Stage 2 stack already running - reusing it."
else
  echo "[*] Stage 2 (Wazuh + endpoint + attacker) isn't up yet - bringing it up..."
  (cd ../stage-2-eyes && bash deploy.sh)
fi

# ---- 2. Load our custom rule (validated, with rollback) ------------------
echo ""
echo "[*] Loading the Stage 3 detection rule..."
bash reload-rules.sh

echo ""
echo "[+] Stage 3 deploy complete."
echo "    Wazuh dashboard : https://localhost:443  (admin / SecretPassword)"
echo "    endpoint        : 10.10.10.10   attacker : 10.10.10.20"
echo ""
echo "Next: ./validate.sh   (checks the pipeline, runs the rule tests, and"
echo "                       fires a real attack to confirm it alerts)"
echo "      ./test-rules.sh  (just the wazuh-logtest rule tests)"
echo "      edit rules/local_rules.xml, then ./reload-rules.sh to apply it."
