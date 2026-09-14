#!/bin/bash
# Simulates routine, benign endpoint activity so the environment has
# realistic background noise from minute one - this is what Stage 2
# (Wazuh) will later have to tell apart from actual attack activity.

echo "$(date -Is) baseline activity tick" >> /var/log/baseline.log

# generates PAM session open/close entries in the auth log, same as a
# real interactive login would
su - student -c 'whoami; ls ~ > /dev/null' 2>>/var/log/baseline.log

# light file churn
touch "/home/student/scratch-$(date +%s).tmp"
find /home/student -name 'scratch-*.tmp' -mmin +5 -delete
