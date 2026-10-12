#!/bin/bash
# Run every tests/*.cases file through the manager's wazuh-logtest and check
# each log line produces (or doesn't produce) the rule ID it's paired with.
# This is how a detection engineer tests a rule without waiting for a real
# attack - feed it a sample log line and see what fires.
set -u
cd "$(dirname "$0")" || exit 1

MANAGER="delab-wazuh-wazuh.manager-1"
PASS=1

if [ "$(docker inspect -f '{{.State.Running}}' "$MANAGER" 2>/dev/null)" != "true" ]; then
  echo "    FAIL: the Wazuh manager ($MANAGER) isn't running. Run ./deploy.sh first."
  exit 1
fi

shopt -s nullglob
CASES=(tests/*.cases)
if [ "${#CASES[@]}" -eq 0 ]; then
  echo "    No test cases found under tests/ - nothing to check."
  exit 0
fi

for file in "${CASES[@]}"; do
  echo "[*] $file"
  # Read the whole file into an array FIRST. We must not keep the file open as
  # the loop's stdin while calling `docker exec -i` inside the loop: with -i,
  # docker attaches to that stdin and consumes it, so wazuh-logtest ends up
  # with no input and the test silently reports "fired=no" for everything.
  mapfile -t LINES < "$file"
  for raw in "${LINES[@]}"; do
    raw="${raw%$'\r'}"                       # tolerate CRLF line endings
    case "$raw" in ''|\#*) continue ;; esac  # skip blanks and comments
    IFS='|' read -r expect rule logline <<<"$raw"
    expect="$(printf '%s' "$expect" | tr -d '[:space:]')"
    rule="$(printf '%s' "$rule" | tr -d '[:space:]')"
    [ -z "$rule" ] && continue

    # Feed the log line via a here-string, exactly like running wazuh-logtest
    # by hand. IMPORTANT: wazuh-logtest writes its report to STDERR, not
    # stdout, so capture both (2>&1) - otherwise $out is always empty and
    # every test looks like it failed.
    out=$(docker exec -i "$MANAGER" /var/ossec/bin/wazuh-logtest <<<"$logline" 2>&1 || true)
    # wazuh-logtest reports the final matching rule's id, but the exact
    # wording differs between versions ("id: '100010'", "Rule id: '100010'",
    # "Rule: 100010 (level ...)"). Match the bare rule number with digit
    # boundaries so the test doesn't depend on that wording.
    if printf '%s' "$out" | grep -Eq "(^|[^0-9])${rule}([^0-9]|$)"; then fired=yes; else fired=no; fi

    if { [ "$expect" = "MATCH" ] && [ "$fired" = "yes" ]; } || \
       { [ "$expect" = "NOMATCH" ] && [ "$fired" = "no" ]; }; then
      echo "    OK   [$expect $rule] ${logline:0:66}"
    else
      echo "    FAIL [$expect $rule] (rule fired=$fired) ${logline:0:60}"
      # Show what wazuh-logtest actually said, so a failure is diagnosable
      # (rule genuinely not firing vs. just an output-wording mismatch).
      printf '%s\n' "$out" | grep -E "Completed filtering|Phase|id:|level:|description:|Rule" | sed 's/^/        | /' | head -n 12
      PASS=0
    fi
  done
done

echo ""
if [ "$PASS" -eq 1 ]; then
  echo "[+] All rule tests passed."
else
  echo "[-] Some rule tests failed. If you just edited a rule, reload it first:"
  echo "    ./reload-rules.sh"
  exit 1
fi
