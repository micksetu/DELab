#!/bin/bash
# Stage 1 acceptance test:
# "Attacker -> Endpoint communication works and the environment can be
#  reset/recreated."
set -e
PASS=1

echo "[*] Checking containers are running..."
for c in stage1-endpoint stage1-attacker; do
  if [ "$(docker inspect -f '{{.State.Running}}' "$c" 2>/dev/null)" != "true" ]; then
    echo "    FAIL: $c is not running"
    PASS=0
  else
    echo "    OK: $c is running"
  fi
done

echo "[*] Checking attacker -> endpoint network reachability..."
if docker exec stage1-attacker sh -c "ping -c1 -W2 10.10.10.10 > /dev/null 2>&1"; then
  echo "    OK: ping succeeded"
else
  echo "    FAIL: ping failed"
  PASS=0
fi

echo "[*] Checking web service is reachable..."
if docker exec stage1-attacker sh -c "curl -s -o /dev/null -w '%{http_code}' http://10.10.10.10 | grep -q 200"; then
  echo "    OK: web service responded 200"
else
  echo "    FAIL: web service did not respond"
  PASS=0
fi

echo "[*] Checking SSH service is open..."
if docker exec stage1-attacker sh -c "nmap -p 22 -Pn 10.10.10.10 | grep -q '22/tcp open'"; then
  echo "    OK: SSH port open on endpoint"
else
  echo "    FAIL: SSH port not detected open"
  PASS=0
fi

echo "[*] Checking baseline activity is generating logs..."
if docker exec stage1-endpoint sh -c "test -s /var/log/baseline.log"; then
  echo "    OK: baseline activity log present"
else
  echo "    FAIL: no baseline activity yet (cron runs once a minute - wait and re-run)"
  PASS=0
fi

echo ""
if [ "$PASS" -eq 1 ]; then
  echo "[+] Stage 1 acceptance test PASSED"
else
  echo "[-] Stage 1 acceptance test FAILED"
  exit 1
fi
