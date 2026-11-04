#!/bin/bash
# Stage 5 (Tier 1) acceptance test:
# "A detected SSH brute force triggers an automated response that actually
#  locks the attacker out of the endpoint, and lifts itself afterwards."
#
# Like every stage, this proves the OUTCOME, not just the wiring:
#   L1  the response path is in place (containers, agent, AR config, responder)
#   L2  the response FIRES and the attacker is genuinely firewalled off
#       (we run the brute force and watch the block land live, then confirm
#        the attacker can no longer even ping the endpoint)
#   L3  the block lifts itself after the timeout (the lab heals, so the next
#       class isn't left with a dead network)
set -u

MANAGER="delab-wazuh-wazuh.manager-1"
ENDPOINT="delab-endpoint"
ATTACKER="delab-attacker"
ENDPOINT_IP="10.10.10.10"
ATTACKER_IP="10.10.10.20"
AR_LOG="/var/ossec/logs/active-responses.log"
PASS=1

# Is the attacker's IP currently DROP'd on the endpoint's INPUT chain?
block_present() {
  docker exec "$ENDPOINT" iptables -S INPUT 2>/dev/null | grep "$ATTACKER_IP" | grep -q "DROP"
}

# ---- Level 1: the response path is in place -----------------------------
echo "[*] Level 1 - response path present"
for c in "$MANAGER" "$ENDPOINT" "$ATTACKER"; do
  if [ "$(docker inspect -f '{{.State.Running}}' "$c" 2>/dev/null)" != "true" ]; then
    echo "    FAIL: $c is not running - run ./deploy.sh"
    PASS=0
  else
    echo "    OK: $c is running"
  fi
done

if docker exec "$MANAGER" /var/ossec/bin/agent_control -l 2>/dev/null | grep "Name: endpoint01," | grep -q "Active"; then
  echo "    OK: Wazuh agent endpoint01 is Active"
else
  echo "    FAIL: agent endpoint01 not Active - the detection that triggers the"
  echo "          response isn't flowing. Deploy/validate Stage 2 first."
  PASS=0
fi

if docker exec "$MANAGER" grep -q "firewall-drop-delab" /var/ossec/etc/ossec.conf 2>/dev/null; then
  echo "    OK: active-response config is loaded on the manager"
else
  echo "    FAIL: the manager has no firewall-drop-delab config - run ./reload-response.sh"
  PASS=0
fi

if docker exec "$ENDPOINT" test -x /var/ossec/active-response/bin/firewall-drop 2>/dev/null; then
  echo "    OK: the firewall-drop responder is present on the agent"
else
  echo "    FAIL: firewall-drop missing on the agent - it ships with wazuh-agent;"
  echo "          rebuild the endpoint with Stage 2's ./deploy.sh"
  PASS=0
fi

# firewall-drop shells out to iptables. The endpoint got iptables (and the
# NET_ADMIN capability) in Stage 2's image - but a stale pre-Stage-5 endpoint
# image wouldn't have it, and the block would then fail at runtime with a
# confusing error. Check for it up front so the failure is legible.
if docker exec "$ENDPOINT" sh -c 'command -v iptables >/dev/null 2>&1'; then
  echo "    OK: iptables is present on the endpoint (firewall-drop needs it)"
else
  echo "    FAIL: iptables is missing on the endpoint - firewall-drop can't run."
  echo "          The endpoint image predates the Stage 5 changes. Rebuild it"
  echo "          with Stage 2's ./deploy.sh (it installs iptables and grants"
  echo "          the NET_ADMIN capability)."
  PASS=0
fi

if ! docker exec "$ATTACKER" sh -c 'command -v sshpass >/dev/null 2>&1'; then
  echo "    FAIL: sshpass isn't in the attacker image - can't generate the attack."
  echo "          Rebuild with Stage 2's ./deploy.sh."
  PASS=0
fi

if [ "$PASS" -ne 1 ]; then
  echo ""
  echo "[-] Stage 5 acceptance test FAILED at level 1 (response path not ready)."
  exit 1
fi

# If a previous run's block is still active, wait for it to lift so our
# baseline reachability check below is honest.
if block_present; then
  echo "[*] A previous block is still active - waiting for it to lift..."
  for _ in $(seq 1 30); do block_present || break; sleep 3; done
fi

# ---- Level 2: the response fires and the attacker is locked out ----------
echo ""
echo "[*] Level 2 - the brute force triggers a real block"

if ! docker exec "$ATTACKER" ping -c1 -W2 "$ENDPOINT_IP" >/dev/null 2>&1; then
  echo "    FAIL: the attacker can't reach the endpoint even before we attack."
  echo "          Something else is wrong - run Stage 2's ./validate.sh."
  exit 1
fi
echo "    OK: baseline - attacker can reach the endpoint (as expected)"

adds_before=$(docker exec "$ENDPOINT" sh -c "grep -c '\"command\":\"add\"' '$AR_LOG' 2>/dev/null" | tr -cd '0-9')
adds_before=${adds_before:-0}

echo "    launching 10 failed SSH logins from the attacker (background)..."
# UserKnownHostsFile=/dev/null makes this immune to the endpoint's host key
# changing on a rebuild - otherwise ssh aborts at host-key verification and
# never reaches password auth (a real gotcha we hit building this stage).
docker exec "$ATTACKER" sh -c '
  for n in $(seq 1 10); do
    sshpass -p "wrong-pw-$n" ssh -o StrictHostKeyChecking=no \
      -o UserKnownHostsFile=/dev/null -o ConnectTimeout=3 \
      student@10.10.10.10 exit 2>/dev/null || true
  done' >/dev/null 2>&1 &
gen_pid=$!

echo "    watching for the block to land on the endpoint..."
BLOCKED=no
for _ in $(seq 1 40); do        # up to ~80s
  if block_present; then BLOCKED=yes; break; fi
  sleep 2
done
wait "$gen_pid" 2>/dev/null || true

if [ "$BLOCKED" = yes ]; then
  echo "    OK: firewall-drop added a DROP rule for the attacker ($ATTACKER_IP)"
  # The real proof: the attacker is now cut off, not just that a rule exists.
  if docker exec "$ATTACKER" ping -c1 -W2 "$ENDPOINT_IP" >/dev/null 2>&1; then
    echo "    WARN: a DROP rule is present but the attacker could still ping -"
    echo "          unexpected; check 'iptables -S INPUT' on the endpoint."
    PASS=0
  else
    echo "    OK: the attacker is now firewalled off the endpoint (ping fails)"
  fi
else
  echo "    FAIL: no block appeared within ~80s. The attack may not have raised"
  echo "          rule 5763, or the response didn't execute. Check:"
  echo "          docker exec $ENDPOINT tail -30 $AR_LOG"
  echo "          docker exec $MANAGER tail -5 /var/ossec/logs/alerts/alerts.json"
  PASS=0
fi

adds_after=$(docker exec "$ENDPOINT" sh -c "grep -c '\"command\":\"add\"' '$AR_LOG' 2>/dev/null" | tr -cd '0-9')
adds_after=${adds_after:-0}
if [ "$adds_after" -gt "$adds_before" ]; then
  echo "    OK: the agent logged a new firewall-drop 'add' (active-responses.log)"
else
  echo "    WARN: no new 'add' line in the agent's active-responses.log"
fi

# ---- Level 3: the block lifts itself -------------------------------------
echo ""
echo "[*] Level 3 - the block auto-lifts after its timeout"
RECOVERED=no
for _ in $(seq 1 40); do        # up to ~120s (timeout is 60s from the add)
  if ! block_present; then RECOVERED=yes; break; fi
  sleep 3
done

if [ "$RECOVERED" = yes ]; then
  if docker exec "$ATTACKER" ping -c1 -W2 "$ENDPOINT_IP" >/dev/null 2>&1; then
    echo "    OK: the DROP rule was removed and the attacker can reach the"
    echo "        endpoint again - the lab healed itself"
  else
    echo "    WARN: the DROP rule is gone but ping still fails - check the"
    echo "          endpoint's iptables and network."
    PASS=0
  fi
else
  echo "    FAIL: the block was still in place after ~120s. Check the timeout"
  echo "          in active-response/local_ar.conf and the agent's AR log:"
  echo "          docker exec $ENDPOINT tail -30 $AR_LOG"
  PASS=0
fi

echo ""
if [ "$PASS" -eq 1 ]; then
  echo "[+] Stage 5 (Tier 1) acceptance test PASSED"
  echo "    Detect (rule 5763) -> respond (firewall-drop the attacker) ->"
  echo "    auto-recover. The incident-response loop is closed."
  echo "    See it in the dashboard: https://localhost:443 (Threat Hunting)."
else
  echo "[-] Stage 5 (Tier 1) acceptance test FAILED (see notes above)"
  exit 1
fi
