#!/bin/bash
set -e
cd "$(dirname "$0")"

MANAGER="delab-wazuh-wazuh.manager-1"

# Stage 3 doesn't own the Wazuh stack - Stage 2 does. A genuine "back to a
# known-good baseline" therefore means rebuilding the Stage 2 stack and then
# re-loading our rule onto it. That's the same (slow) full rebuild as the
# earlier stages; if you only edited a rule and want it re-applied, use
# ./reload-rules.sh instead, which takes seconds.
echo "[*] Stage 3 reset: full teardown + rebuild of the lab, then reload the rule."
echo "    (For a quick rule re-apply without rebuilding, use ./reload-rules.sh.)"

(cd ../stage-2-eyes && bash reset.sh)

echo "[*] Re-loading the Stage 3 detection rule onto the fresh stack..."
# Give the freshly-started manager a moment to be ready for exec.
for _ in $(seq 1 12); do
  [ "$(docker inspect -f '{{.State.Running}}' "$MANAGER" 2>/dev/null)" = "true" ] && break
  sleep 5
done
bash reload-rules.sh

echo "[+] Stage 3 reset complete."
