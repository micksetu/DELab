#!/bin/bash
set -e

# ---- Basic users -----------------------------------------------------
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

# ---- Basic files -------------------------------------------------------
mkdir -p /home/student
cat > /home/student/notes.txt <<'EOF'
Reminder: rotate the shared drive password before Friday.
EOF
chown student:student /home/student/notes.txt

mkdir -p /var/www/html
cat > /var/www/html/index.html <<'EOF'
<html><body><h1>Stage 1 Endpoint</h1><p>Baseline web service.</p></body></html>
EOF

mkdir -p /opt/baseline
cat > /opt/baseline/readme.txt <<'EOF'
This is the Stage 1 baseline endpoint for the detection engineering lab.
EOF

# ---- Services ------------------------------------------------------------
mkdir -p /run/sshd
ssh-keygen -A
sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config

# call daemons directly - no init system to hand off to inside a container,
# so the 'service' wrapper is unreliable here
mkdir -p /var/spool/rsyslog
rsyslogd || echo "WARNING: rsyslogd failed to start, continuing without it"

python3 -m http.server 80 --directory /var/www/html &

echo "* * * * * root /opt/baseline_activity.sh >> /var/log/baseline.log 2>&1" > /etc/cron.d/baseline
chmod 0644 /etc/cron.d/baseline
cron || echo "WARNING: cron failed to start, continuing without it"

# SSH stays in the foreground so the container has a PID 1 to track
exec /usr/sbin/sshd -D -e
