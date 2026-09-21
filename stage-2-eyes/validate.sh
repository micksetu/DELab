#!/bin/bash
# Stage 2 acceptance test:
# "A known activity produces an identifiable event in Wazuh."
# This script checks the pipeline is wired up; actually generating and
# finding an event is the students' Stage 2 exercise (see STUDENT-TOUR.md
# once it exists).
set -e
PASS=1

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
  CID=$(docker ps --filter "name=${name}" --format '{{.ID}}' | head -n1)
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

echo "[*] Checking the Wazuh agent on the endpoint has connected to the manager..."
if docker exec stage2-endpoint sh -c "grep -q 'Connected to the server' /var/ossec/logs/ossec.log 2>/dev/null"; then
  echo "    OK: agent reports connected"
else
  echo "    WARN: agent not showing connected yet - this can take up to a minute"
  echo "          after deploy. Re-run this script, or check:"
  echo "          docker exec stage2-endpoint tail -30 /var/ossec/logs/ossec.log"
  PASS=0
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
