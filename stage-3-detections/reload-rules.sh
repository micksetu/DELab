#!/bin/bash
# Load rules/local_rules.xml into the running Wazuh manager - safely.
#
# Why not a Compose bind-mount? A bind-mount override was flaky for this
# exact stack while Stage 2 was being built, so we copy the file into the
# running container and restart Wazuh's services to pick it up. It's quick
# and easy to re-run every time you edit a rule, without a full redeploy.
#
# The important part: we VALIDATE the ruleset with `wazuh-analysisd -t`
# before restarting. A single XML typo would otherwise stop the manager
# from coming back up and knock the agent offline - exactly the kind of
# confusing breakage we hit in Stage 2. If validation fails, we put the
# previous rules file back and leave the manager running.
set -u
cd "$(dirname "$0")" || exit 1

MANAGER="delab-wazuh-wazuh.manager-1"
RULES_SRC="rules/local_rules.xml"
RULES_DST="/var/ossec/etc/rules/local_rules.xml"

if [ "$(docker inspect -f '{{.State.Running}}' "$MANAGER" 2>/dev/null)" != "true" ]; then
  echo "    FAIL: the Wazuh manager ($MANAGER) isn't running."
  echo "    Run ./deploy.sh first (it brings up Stage 2 if needed)."
  exit 1
fi

if [ ! -f "$RULES_SRC" ]; then
  echo "    FAIL: $RULES_SRC not found."
  exit 1
fi

echo "[*] Backing up the manager's current local_rules.xml..."
docker exec "$MANAGER" sh -c "cp -f '$RULES_DST' '${RULES_DST}.delab-bak' 2>/dev/null || true"

echo "[*] Copying $RULES_SRC into the manager..."
docker cp "$RULES_SRC" "$MANAGER:$RULES_DST"
# The manager runs wazuh-analysisd as the 'wazuh' user; make sure it can
# read the file we just dropped in as root.
docker exec "$MANAGER" sh -c "chown root:wazuh '$RULES_DST' 2>/dev/null || true; chmod 660 '$RULES_DST' 2>/dev/null || true"

echo "[*] Validating the ruleset (wazuh-analysisd -t)..."
if docker exec "$MANAGER" /var/ossec/bin/wazuh-analysisd -t; then
  echo "    ruleset OK - restarting Wazuh to load it..."
  docker exec "$MANAGER" /var/ossec/bin/wazuh-control restart >/dev/null
  echo "[+] Rules loaded."
else
  echo ""
  echo "    FAIL: the ruleset has an error (see the message above)."
  echo "          Rolling back to the previous local_rules.xml so the"
  echo "          manager keeps working. Fix $RULES_SRC and re-run."
  docker exec "$MANAGER" sh -c "cp -f '${RULES_DST}.delab-bak' '$RULES_DST' 2>/dev/null || true"
  exit 1
fi
