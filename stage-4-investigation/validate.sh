#!/bin/bash
# Stage 4 acceptance test:
# "Starting from a Wazuh alert, an investigator can retrieve live endpoint
#  evidence from Velociraptor."
#
# Like the other stages, this proves the OUTCOME, not just the plumbing:
#   1. the delab pipeline + both agents are healthy
#   2. the Velociraptor client is actually ENROLLED (the server sees it)
#   3. the server can read LIVE host facts from the endpoint - i.e. there is
#      real evidence to investigate, not just a connected socket
set -u

MANAGER="delab-wazuh-wazuh.manager-1"
VELO="delab-velociraptor"
ENDPOINT="delab-endpoint"
SERVER_CONF=/etc/velociraptor/server.config.yaml
API_CONF=/etc/velociraptor/admin.api.yaml
PASS=1

# Run a VQL query against the LIVE server and return JSONL (one row per line).
#
# This must go through the server's API, not `query --config server.config.yaml`
# - the latter spins up a throwaway context that can't see the running server's
# enrolled clients (clients() comes back empty). We issue an API cert under the
# existing 'admin' user (already has the administrator role, so no ACL grant is
# needed) and query with it.
velo_query() {
  docker exec "$VELO" sh -c "test -f $API_CONF || velociraptor --config $SERVER_CONF config api_client --name admin --role administrator $API_CONF >/dev/null 2>&1"
  docker exec "$VELO" velociraptor --api_config "$API_CONF" query --format jsonl "$1" 2>/dev/null
}

# ---- Level 1: pipeline health -------------------------------------------
echo "[*] Level 1 - pipeline health"
for c in "$MANAGER" "$ENDPOINT" delab-attacker "$VELO"; do
  if [ "$(docker inspect -f '{{.State.Running}}' "$c" 2>/dev/null)" != "true" ]; then
    echo "    FAIL: $c is not running - run ./deploy.sh"
    PASS=0
  else
    echo "    OK: $c is running"
  fi
done

if docker exec "$MANAGER" /var/ossec/bin/agent_control -l 2>/dev/null | grep "Name: endpoint01," | grep -q "Active"; then
  echo "    OK: Wazuh agent endpoint01 is Active (the Stage 3 alert path still works)"
else
  echo "    WARN: Wazuh agent endpoint01 not Active yet - give it a minute after deploy"
  PASS=0
fi

# No point checking Velociraptor if the basics are down.
if [ "$PASS" -ne 1 ]; then
  echo ""
  echo "[-] Stage 4 acceptance test FAILED at level 1 (pipeline not healthy)."
  exit 1
fi

# ---- Level 2: the Velociraptor client is enrolled -----------------------
echo ""
echo "[*] Level 2 - Velociraptor client enrolment"

if docker exec "$ENDPOINT" pgrep -f 'velociraptor.*client' >/dev/null 2>&1; then
  echo "    OK: the Velociraptor client process is running on the endpoint"
else
  echo "    FAIL: no Velociraptor client process on the endpoint. Check:"
  echo "          docker exec $ENDPOINT tail -30 /var/log/velociraptor-client.log"
  PASS=0
fi

if velo_query "SELECT os_info.hostname AS host FROM clients()" | grep -qi "endpoint01"; then
  echo "    OK: the server lists endpoint01 as an enrolled client"
else
  echo "    FAIL: the server does not see endpoint01 enrolled yet."
  echo "          The client can take a minute on first run - wait and re-run."
  echo "          If it persists: docker exec $ENDPOINT tail -30 /var/log/velociraptor-client.log"
  PASS=0
fi

# ---- Level 3: there is live evidence to investigate ----------------------
echo ""
echo "[*] Level 3 - live endpoint evidence (not just a connected socket)"
# The client reports host facts on enrolment; being able to read them back
# from the server is the smallest honest proof that an investigator has real
# data to work with. (Running full artifact collections is the student
# exercise - see STUDENT-TOUR.md.)
HOSTROW=$(velo_query "SELECT os_info.hostname AS host, os_info.system AS os, os_info.release AS rel FROM clients()")
if echo "$HOSTROW" | grep -qi "endpoint01" && echo "$HOSTROW" | grep -qi "linux"; then
  echo "    OK: the server has live host facts from the endpoint:"
  echo "$HOSTROW" | grep -i "endpoint01" | head -n1 | sed 's/^/        /'
else
  echo "    FAIL: couldn't read host facts for endpoint01 from the server."
  echo "          The client may be enrolled but not yet reporting - wait and re-run."
  PASS=0
fi

echo ""
if [ "$PASS" -eq 1 ]; then
  echo "[+] Stage 4 acceptance test PASSED"
  echo "    Wazuh raises the alert; Velociraptor has live evidence from the same"
  echo "    endpoint. Open the GUI (https://localhost:8889) and investigate:"
  echo "    search 'endpoint01' and run a collection (see STUDENT-TOUR.md)."
else
  echo "[-] Stage 4 acceptance test FAILED (see notes above)"
  exit 1
fi
