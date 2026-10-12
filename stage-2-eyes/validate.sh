#!/bin/bash
# Stage 2 acceptance test:
# "A known activity produces an identifiable event in Wazuh."
# As well as checking the pipeline is wired up (containers, agent enrolled),
# this proves the OUTCOME: it generates a known activity on the endpoint and
# confirms the manager actually records it as an alert. Checking only that the
# agent "connected" is what let an sshd logging misconfig hide an entirely
# dead detection path in earlier versions of this lab.
PASS=1
MANAGER="delab-wazuh-wazuh.manager-1"
AGENT_NAME="endpoint01"
ALERTS="/var/ossec/logs/alerts/alerts.json"

echo "[*] Checking our containers are running..."
for c in delab-endpoint delab-attacker; do
  if [ "$(docker inspect -f '{{.State.Running}}' "$c" 2>/dev/null)" != "true" ]; then
    echo "    FAIL: $c is not running"
    PASS=0
  else
    echo "    OK: $c is running"
  fi
done

echo "[*] Checking the Wazuh stack is running..."
for name in "wazuh.manager" "wazuh.indexer" "wazuh.dashboard"; do
  CID=$(docker ps --filter "name=delab-wazuh-${name}" --format '{{.ID}}' | head -n1)
  if [ -z "$CID" ]; then
    echo "    FAIL: $name container not found/running"
    PASS=0
  else
    echo "    OK: $name running ($CID)"
  fi
done

echo "[*] Checking attacker -> endpoint reachability (Stage 1 network, unchanged)..."
if docker exec delab-attacker sh -c "ping -c1 -W2 10.10.10.10 > /dev/null 2>&1"; then
  echo "    OK: ping succeeded"
else
  echo "    FAIL: ping failed"
  PASS=0
fi

echo "[*] Checking the endpoint can find the Wazuh manager on the network..."
if docker exec delab-endpoint getent hosts wazuh.manager > /dev/null 2>&1; then
  echo "    OK: wazuh.manager resolves ($(docker exec delab-endpoint getent hosts wazuh.manager | awk '{print $1}'))"
else
  echo "    FAIL: endpoint can't resolve wazuh.manager - it isn't on the Wazuh network."
  echo "          Re-run ./deploy.sh."
  PASS=0
fi

echo "[*] Checking the manager lists the agent as Active..."
# The manager's view is what the dashboard shows, so check that rather than
# only the agent's own log.
STATUS=$(docker exec "$MANAGER" /var/ossec/bin/agent_control -l 2>/dev/null | grep "Name: ${AGENT_NAME},")
if echo "$STATUS" | grep -q "Active"; then
  echo "    OK: $AGENT_NAME is Active on the manager"
else
  PASS=0
  AGENT_LOG=$(docker exec delab-endpoint tail -50 /var/ossec/logs/ossec.log 2>/dev/null)
  if echo "$AGENT_LOG" | grep -q "Duplicate agent name"; then
    echo "    FAIL: the manager still has an old '$AGENT_NAME' registration and"
    echo "          is rejecting this endpoint. Re-run ./deploy.sh - it removes"
    echo "          the old registration and recreates the endpoint."
  else
    echo "    WARN: $AGENT_NAME not Active yet${STATUS:+ (manager says: $(echo "$STATUS" | sed -E 's/.*, //'))}."
    echo "          This can take up to a minute after deploy - wait and re-run."
    echo "          If it persists, check the agent's log:"
    echo "          docker exec delab-endpoint tail -30 /var/ossec/logs/ossec.log"
  fi
fi

echo "[*] Checking baseline activity is actually running on the endpoint..."
# A stale/missing baseline log means cron isn't firing - later stages rely
# on this "normal" noise to tell benign activity apart from an attack.
if docker exec delab-endpoint sh -c '[ -s /var/log/baseline.log ] && [ $(($(date +%s) - $(date -r /var/log/baseline.log +%s))) -lt 120 ]' 2>/dev/null; then
  echo "    OK: baseline activity log updated within the last 2 minutes"
else
  echo "    WARN: baseline activity log missing or stale - cron may not be running."
  echo "          Check: docker exec delab-endpoint tail -5 /var/log/baseline.log"
  echo "                 docker exec delab-endpoint pgrep cron"
  PASS=0
fi

echo "[*] End-to-end: a known activity should produce an identifiable alert..."
# The heart of Stage 2's acceptance criterion: prove that activity on the
# endpoint actually becomes telemetry the manager records - not just that the
# agent is connected. Stage 2 has no custom rules, so we rely on Wazuh's
# BUILT-IN ruleset: repeated failed SSH logins raise rule 5760 (per failure)
# and, past 8 in 120s from one IP, the brute-force rule 5763.
count_sshd_fail() {
  local n
  n=$(docker exec "$MANAGER" sh -c "grep -Ec '\"id\":\"(5760|5763|5716)\"' $ALERTS 2>/dev/null" || true)
  n=$(printf '%s' "$n" | head -n1 | tr -cd '0-9')
  echo "${n:-0}"
}
if docker exec delab-attacker sh -c 'command -v sshpass >/dev/null 2>&1'; then
  before_fail=$(count_sshd_fail)
  echo "    generating 10 failed SSH logins as 'student' from the attacker..."
  docker exec delab-attacker sh -c '
    for n in $(seq 1 10); do
      sshpass -p "wrong-pw-$n" ssh -o StrictHostKeyChecking=no -o ConnectTimeout=3 \
        student@10.10.10.10 exit 2>/dev/null || true
    done'
  found_alert=no
  for _ in $(seq 1 12); do   # up to ~60s for the alert to be written
    [ "$(count_sshd_fail)" -gt "$before_fail" ] && { found_alert=yes; break; }
    sleep 5
  done
  if [ "$found_alert" = yes ]; then
    echo "    OK: the failed logins produced SSH authentication alerts in Wazuh"
  else
    echo "    FAIL: no SSH auth alert appeared within ~60s - activity on the"
    echo "          endpoint is not reaching Wazuh as telemetry. Check:"
    echo "          docker exec delab-endpoint tail -20 /var/log/auth.log"
    echo "          docker exec $MANAGER tail -5 $ALERTS"
    PASS=0
  fi
else
  echo "    WARN: sshpass not in the attacker image - skipping the end-to-end"
  echo "          alert check. Rebuild with ./deploy.sh to include it."
fi

echo ""
if [ "$PASS" -eq 1 ]; then
  echo "[+] Stage 2 acceptance test PASSED"
  echo "    Log into the dashboard (https://localhost:443) and check"
  echo "    Agents management > Summary to see it listed as active."
else
  echo "[-] Stage 2 acceptance test FAILED (see notes above)"
  exit 1
fi
