FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    openssh-server \
    sudo \
    cron \
    rsyslog \
    python3 \
    iputils-ping \
    net-tools \
    curl \
    ca-certificates \
    gnupg \
    && rm -rf /var/lib/apt/lists/*

# ---- Wazuh agent -------------------------------------------------------
# Same apt repo / steps as the official docs (installation-guide/wazuh-agent).
# Not pinning an exact package build here - the 4.x repo tracks the current
# stable line, and agent/manager compatibility only requires manager >= agent.
RUN curl -fsSL https://packages.wazuh.com/key/GPG-KEY-WAZUH | \
      gpg --no-default-keyring --keyring gnupg-ring:/usr/share/keyrings/wazuh.gpg --import && \
    chmod 644 /usr/share/keyrings/wazuh.gpg && \
    echo "deb [signed-by=/usr/share/keyrings/wazuh.gpg] https://packages.wazuh.com/4.x/apt/ stable main" \
      > /etc/apt/sources.list.d/wazuh.list && \
    apt-get update && \
    apt-get install -y --no-install-recommends wazuh-agent && \
    rm -rf /var/lib/apt/lists/*

RUN mkdir -p /var/run/sshd

COPY entrypoint.sh /entrypoint.sh
COPY baseline_activity.sh /opt/baseline_activity.sh
RUN chmod +x /entrypoint.sh /opt/baseline_activity.sh

EXPOSE 22 80

ENTRYPOINT ["/entrypoint.sh"]
