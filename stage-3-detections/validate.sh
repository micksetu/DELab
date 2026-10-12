#!/bin/bash
# Stage 3 acceptance test:
# "A controlled attack produces the expected alert, and benign activity
#  does not trigger the detection."
#
# Three levels:
#   1. the Stage 2 pipeline is healthy (manager, endpoint, agent)
#   2. the rule tests pass   (wazuh-logtest, via ./test-rules.sh)
#   3. end-to-end, for real: a benign login raises NO custom alert, and a
#      bruteforce+login DOES - checked against the manager's alerts.json
#
# Level 3 actually generates events on the endpoint, so this is not a
# read-only check. That's deliberate - it's the acceptance test.
set -u
cd "$(dirname "$0")" || exit 1

MANAGER="delab-wazuh-wazuh.manager-1"
ATTACKER="delab-attacker"
TARGET="10.10.10.10"
ALERTS="/var/ossec/logs/alerts/alerts.json"
PASS=1

count_rule() {  # count_rule <rule_id> -> number of alerts for that rule (0 if none/missing)
  local n
  n=$(docker exec "$MANAGER" sh -c "grep -c '\"id\":\"$1\"' $ALERTS 2>/dev/null" || true)
  # grep -c prints 0 and exits 1 when there are no matches; empty if the
  # file doesn't exist yet. Normalise to a single integer.
  n=$(printf '%s' "$n" | head -n1 | tr -cd '0-9')
  echo "${n:-0}"
}

# ---- Level 1: pipeline health -------------------------------------------
echo "[*] Level 1 - pipeline health"
for c in "$MANAGER" delab-endpoint "$ATTACKER"; do
  if [ "$(docker inspect -f '{{.State.Running}}' "$c" 2>/dev/null)" != "true" ]; then
    echo "    FAIL: $c is not running - run ./deploy.sh"
    PASS=0
  else
    echo "    OK: $c is running"
  fi
done

if docker exec "$MANAGER" /var/ossec/bin/agent_control -l 2>/dev/null | grep "Name: endpoint01," | grep -q "Active"; then
  echo "    OK: agent endpoint01 is Active on the manager"
else
  echo "    WARN: agent endpoint01 not Active yet - give it a minute after deploy"
  PASS=0
fi

# If the pipeline is already broken, the deeper checks will only produce
# noise - stop here.
if [ "$PASS" -ne 1 ]; then
  echo ""
  echo "[-] Stage 3 acceptance test FAILED at level 1 (pipeline not healthy)."
  exit 1
fi

# ---- Level 2: rule tests (wazuh-logtest) --------------------------------
echo ""
echo "[*] Level 2 - rule tests (wazuh-logtest)"
if bash test-rules.sh; then
  echo "    OK: rule tests passed"
else
  echo "    FAIL: rule tests failed (see above). Is the rule loaded? ./reload-rules.sh"
  PASS=0
fi

# ---- Level 3: end-to-end, real events -----------------------------------
echo ""
echo "[*] Level 3 - end-to-end (this generates real activity on the endpoint)"

before_100010=$(count_rule 100010)

echo "    - benign check: a successful 'admin' login should NOT raise rule 100010"
docker exec "$ATTACKER" sh -c "sshpass -p 'AdminP@ssw0rd!' ssh -o StrictHostKeyChecking=no -o ConnectTimeout=3 admin@$TARGET exit" >/dev/null 2>&1 || true
sleep 20
after_admin=$(count_rule 100010)
if [ "$after_admin" -eq "$before_100010" ]; then
  echo "      OK: admin login raised no 'student' alert (no false positive)"
else
  echo "      FAIL: rule 100010 count rose on an admin login ($before_100010 -> $after_admin)"
  PASS=0
fi

# Detection check (100010) uses a CLEAN login, done BEFORE any bruteforce.
# Running it after a burst of failed logins risks the success being refused
# (lockout/tarpit), which would make a working rule look broken - so test the
# custom detection on its own first, then test the bruteforce rule separately.
echo "    - detection check: a 'student' login SHOULD raise rule 100010"
before_100010=$(count_rule 100010)
docker exec "$ATTACKER" sh -c "sshpass -p password123 ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 student@$TARGET exit" >/dev/null 2>&1 || true
found_100010=no
for _ in $(seq 1 12); do   # ~60s; alerts.json can lag a real event by a bit
  [ "$(count_rule 100010)" -gt "$before_100010" ] && { found_100010=yes; break; }
  sleep 5
done
if [ "$found_100010" = yes ]; then
  echo "      OK: custom rule 100010 fired on the real 'student' login"
else
  echo "      FAIL: rule 100010 did not fire end-to-end within ~60s"
  echo "            (100010 alerts before=$before_100010, now=$(count_rule 100010))."
  echo "            Check: the login succeeded, the agent collects /var/log/auth.log,"
  echo "            and the rule is loaded (./reload-rules.sh; ./test-rules.sh)."
  PASS=0
fi

echo "    - bruteforce check: repeated failures SHOULD raise built-in rule 5763"
before_5763=$(count_rule 5763)
bash scenarios/bruteforce-then-login.sh >/dev/null 2>&1 || true
found_5763=no
for _ in $(seq 1 12); do
  [ "$(count_rule 5763)" -gt "$before_5763" ] && { found_5763=yes; break; }
  sleep 5
done
if [ "$found_5763" = yes ]; then
  echo "      OK: built-in bruteforce rule 5763 fired"
else
  echo "      WARN: built-in bruteforce rule 5763 did not fire - the failed"
  echo "            attempts may not have crossed the 8-in-120s threshold."
fi

echo ""
if [ "$PASS" -eq 1 ]; then
  echo "[+] Stage 3 acceptance test PASSED"
  echo "    Custom detection fires on the real attack and stays quiet on"
  echo "    benign activity. Open Threat Hunting in the dashboard to see them."
else
  echo "[-] Stage 3 acceptance test FAILED (see notes above)"
  exit 1
fi
