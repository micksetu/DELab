#!/bin/bash
# A predictable attack that always produces the alerts Stage 3 is about:
#   - repeated failed SSH logins as 'student'  -> rule 5760 (each failure)
#                                                 and 5763 (brute-force
#                                                 correlation: 8 failures
#                                                 from one IP within 120s)
#   - one successful login as 'student'         -> custom rule 100010 (T1078)
#
# Runs from the attacker container against the endpoint, over the same
# isolated range network as every other stage. Unlike the Stage 1 hydra
# script, the number of attempts here is fixed, so the correlation rule
# fires every time rather than depending on the wordlist length.
set -u

ATTACKER="delab-attacker"
TARGET="${1:-10.10.10.10}"

if [ "$(docker inspect -f '{{.State.Running}}' "$ATTACKER" 2>/dev/null)" != "true" ]; then
  echo "FAIL: $ATTACKER isn't running - deploy Stage 2/3 first (./deploy.sh)."
  exit 1
fi

# The scenario drives SSH with sshpass. If the attacker image predates the
# sshpass addition, every attempt below would silently do nothing and no
# alerts would appear - so fail loudly and say how to fix it instead.
if ! docker exec "$ATTACKER" sh -c 'command -v sshpass >/dev/null 2>&1'; then
  echo "FAIL: 'sshpass' isn't installed in $ATTACKER."
  echo "      Rebuild the attacker image: (cd ../stage-2-eyes && ./deploy.sh)"
  echo "      which rebuilds it with sshpass included."
  exit 1
fi

echo "[*] 12 failed SSH logins as 'student' (wrong passwords)..."
docker exec "$ATTACKER" sh -c '
  for n in $(seq 1 12); do
    sshpass -p "wrong-pw-$n" ssh -o StrictHostKeyChecking=no -o ConnectTimeout=3 \
      student@'"$TARGET"' exit 2>/dev/null || true
  done
'

echo "[*] One successful SSH login as 'student' (correct password)..."
docker exec "$ATTACKER" sh -c '
  sshpass -p password123 ssh -o StrictHostKeyChecking=no -o ConnectTimeout=3 \
    student@'"$TARGET"' "whoami; id" >/dev/null 2>&1 || true
'

echo "[+] Done. Give it ~30s, then look in the dashboard (Threat Hunting)"
echo "    or run ./validate.sh to confirm the alerts landed."
