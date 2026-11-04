#!/bin/bash
# Load active-response/local_ar.conf into the running Wazuh manager - safely.
#
# Same idea as Stage 3's reload-rules.sh, for active response instead of
# rules. A Compose bind-mount of ossec.conf was flaky for this stack, so we
# edit the config inside the running manager and restart it. Quick to re-run
# whenever you change a response.
#
# Safety: we keep our block between two markers so re-runs are idempotent
# (the old block is removed before the new one is appended), VALIDATE the
# config with `wazuh-analysisd -t` before restarting, and roll back to the
# previous ossec.conf if validation fails - so a typo can't strand the
# manager (the kind of confusing breakage we hit in Stage 2).
set -u
cd "$(dirname "$0")" || exit 1

MANAGER="delab-wazuh-wazuh.manager-1"
CONF="/var/ossec/etc/ossec.conf"
AR_SRC="active-response/local_ar.conf"

if [ "$(docker inspect -f '{{.State.Running}}' "$MANAGER" 2>/dev/null)" != "true" ]; then
  echo "    FAIL: the Wazuh manager ($MANAGER) isn't running."
  echo "    Run ./deploy.sh first (it brings up Stages 2-4 if needed)."
  exit 1
fi

if [ ! -f "$AR_SRC" ]; then
  echo "    FAIL: $AR_SRC not found."
  exit 1
fi

echo "[*] Backing up the manager's current ossec.conf..."
docker exec "$MANAGER" sh -c "cp -f '$CONF' '${CONF}.delab-ar-bak'"

echo "[*] Removing any previous DELab active-response block (idempotent)..."
docker exec "$MANAGER" sed -i '/DELAB-STAGE5-AR-START/,/DELAB-STAGE5-AR-END/d' "$CONF"

echo "[*] Injecting active-response/local_ar.conf into the manager..."
docker cp "$AR_SRC" "$MANAGER:/tmp/delab_ar.conf"
docker exec "$MANAGER" sh -c "printf '\n' >> '$CONF'; cat /tmp/delab_ar.conf >> '$CONF'; rm -f /tmp/delab_ar.conf"
# ossec.conf is read by wazuh services running as the 'wazuh' user; keep it
# owned/permissioned the way the stack expects.
docker exec "$MANAGER" sh -c "chown root:wazuh '$CONF' 2>/dev/null || true; chmod 660 '$CONF' 2>/dev/null || true"

echo "[*] Validating the configuration (wazuh-analysisd -t)..."
if docker exec "$MANAGER" /var/ossec/bin/wazuh-analysisd -t; then
  echo "    config OK - restarting Wazuh to load it..."
  docker exec "$MANAGER" /var/ossec/bin/wazuh-control restart >/dev/null
  # Confirm the manager actually came back up.
  sleep 3
  if [ "$(docker inspect -f '{{.State.Running}}' "$MANAGER" 2>/dev/null)" = "true" ]; then
    echo "[+] Active response loaded."
    echo "    Trigger: rule 5763 (SSH brute force)  ->  firewall-drop on the"
    echo "    agent that saw it, auto-lifted after 60s."
  else
    echo "    WARN: manager not reporting running yet - give it a few seconds"
    echo "          and check: docker ps | grep manager"
  fi
else
  echo ""
  echo "    FAIL: the configuration has an error (see the message above)."
  echo "          Rolling back to the previous ossec.conf so the manager"
  echo "          keeps working. Fix $AR_SRC and re-run."
  docker exec "$MANAGER" sh -c "cp -f '${CONF}.delab-ar-bak' '$CONF'"
  exit 1
fi
