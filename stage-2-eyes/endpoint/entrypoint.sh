#!/bin/bash
set -e

# ---- Basic users (same as Stage 1) --------------------------------------
if ! id "admin" &>/dev/null; then
  useradd -m -s /bin/bash admin
  echo "admin:AdminP@ssw0rd!" | chpasswd
  usermod -aG sudo admin
fi

if ! id "student" &>/dev/null; then
  useradd -m -s /bin/bash student
  echo "student:password123" | chpasswd
fi

if ! id -u websvc &>/dev/null; then
  useradd -r -s /usr/sbin/nologin websvc
fi

# ---- Basic files (same as Stage 1) --------------------------------------
mkdir -p /home/student
cat > /home/student/notes.txt <<'EOF'
Reminder: rotate the shared drive password before Friday.
EOF
chown student:student /home/student/notes.txt

mkdir -p /var/www/html
cat > /var/www/html/index.html <<'EOF'
<html><body><h1>Stage 2 Endpoint</h1><p>Now with a Wazuh agent installed.</p></body></html>
EOF

mkdir -p /opt/baseline
cat > /opt/baseline/readme.txt <<'EOF'
This is the Stage 2 endpoint for the detection engineering lab.
EOF

# ---- Services (same as Stage 1) -----------------------------------------
mkdir -p /run/sshd
ssh-keygen -A
sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config

mkdir -p /var/spool/rsyslog
rsyslogd || echo "WARNING: rsyslogd failed to start, continuing without it"

python3 -m http.server 80 --directory /var/www/html &

echo "* * * * * root /opt/baseline_activity.sh >> /var/log/baseline.log 2>&1" > /etc/cron.d/baseline
chmod 0644 /etc/cron.d/baseline
cron || echo "WARNING: cron failed to start, continuing without it"

# ---- Wazuh agent (new in Stage 2) ----------------------------------------
# Point the agent at the manager. The installed default config ships with
# the placeholder MANAGER_IP in <client><server><address> - swap it for the
# manager's container hostname on the shared Wazuh network.
#
# No enrollment password: the Wazuh network is only reachable by containers
# we've explicitly joined to it, so for a disposable teaching lab this is
# an acceptable simplification rather than something to fight to enable.
CONF=/var/ossec/etc/ossec.conf
MANAGER_HOST="${WAZUH_MANAGER_HOST:-wazuh.manager}"
if [ -f "$CONF" ]; then
  sed -i "s/MANAGER_IP/${MANAGER_HOST}/" "$CONF"
  sed -i '/<enrollment>/,/<\/enrollment>/d' "$CONF"
  sed -i "/<\/client>/i\\
    <enrollment>\\
      <enabled>yes</enabled>\\
      <manager_address>${MANAGER_HOST}</manager_address>\\
      <port>1515</port>\\
    </enrollment>" "$CONF"
fi

# wazuh-agentd enrolls itself against wazuh-authd on first connect, then
# keeps retrying in the background if the manager isn't reachable yet -
# so it's fine if this starts slightly before the manager is fully up.
/var/ossec/bin/wazuh-control start || echo "WARNING: wazuh-agent failed to start, continuing without it"

# SSH stays in the foreground so the container has a PID 1 to track
exec /usr/sbin/sshd -D -e
