#!/bin/bash
# Stage 2 acceptance test:
# "A known activity produces an identifiable event in Wazuh."
# This script checks the pipeline is wired up; actually generating and
# finding an event is the students' Stage 2 exercise (see STUDENT-TOUR.md).
PASS=1
MANAGER="stage2-eyes-wazuh-wazuh.manager-1"
AGENT_NAME="endpoint01"

echo "[*] Checking our containers are running..."
for c in stage2-endpoint stage2-attacker; do
  if [ "$(docker inspect -f '{{.State.Running}}' "$c" 2>/dev/null)" != "true" ]; then
    echo "    FAIL: $c is not running"
    PASS=0
  else
    echo "    OK: $c is running"
  fi
done

echo "[*] Checking the Wazuh stack is running..."
for name in "wazuh.manager" "wazuh.indexer" "wazuh.dashboard"; do
  CID=$(docker ps --filter "name=stage2-eyes-wazuh-${name}" --format '{{.ID}}' | head -n1)
  if [ -z "$CID" ]; then
    echo "    FAIL: $name container not found/running"
    PASS=0
  else
    echo "    OK: $name running ($CID)"
  fi
done

echo "[*] Checking attacker -> endpoint reachability (Stage 1 network, unchanged)..."
if docker exec stage2-attacker sh -c "ping -c1 -W2 10.10.10.10 > /dev/null 2>&1"; then
  echo "    OK: ping succeeded"
else
  echo "    FAIL: ping failed"
  PASS=0
fi

echo "[*] Checking the endpoint can find the Wazuh manager on the network..."
if docker exec stage2-endpoint getent hosts wazuh.manager > /dev/null 2>&1; then
  echo "    OK: wazuh.manager resolves ($(docker exec stage2-endpoint getent hosts wazuh.manager | awk '{print $1}'))"
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
  AGENT_LOG=$(docker exec stage2-endpoint tail -50 /var/ossec/logs/ossec.log 2>/dev/null)
  if echo "$AGENT_LOG" | grep -q "Duplicate agent name"; then
    echo "    FAIL: the manager still has an old '$AGENT_NAME' registration and"
    echo "          is rejecting this endpoint. Re-run ./deploy.sh - it removes"
    echo "          the old registration and recreates the endpoint."
  else
    echo "    WARN: $AGENT_NAME not Active yet${STATUS:+ (manager says: $(echo "$STATUS" | sed -E 's/.*, //'))}."
    echo "          This can take up to a minute after deploy - wait and re-run."
    echo "          If it persists, check the agent's log:"
    echo "          docker exec stage2-endpoint tail -30 /var/ossec/logs/ossec.log"
  fi
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
