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
# Pinned to the same release as the manager: Wazuh rejects agents newer than
# the manager, so an unpinned install breaks enrollment as soon as the 4.x
# repo moves past the manager's version. WAZUH_VERSION is passed in by
# docker-compose.yml from deploy.sh's WAZUH_TAG - don't set it here.
ARG WAZUH_VERSION
RUN test -n "$WAZUH_VERSION" || (echo "WAZUH_VERSION build arg not set - run ./deploy.sh" && exit 1)
RUN curl -fsSL https://packages.wazuh.com/key/GPG-KEY-WAZUH | \
      gpg --no-default-keyring --keyring gnupg-ring:/usr/share/keyrings/wazuh.gpg --import && \
    chmod 644 /usr/share/keyrings/wazuh.gpg && \
    echo "deb [signed-by=/usr/share/keyrings/wazuh.gpg] https://packages.wazuh.com/4.x/apt/ stable main" \
      > /etc/apt/sources.list.d/wazuh.list && \
    apt-get update && \
    apt-get install -y --no-install-recommends "wazuh-agent=${WAZUH_VERSION}-1" && \
    apt-mark hold wazuh-agent && \
    rm -rf /var/lib/apt/lists/*

RUN mkdir -p /var/run/sshd

COPY entrypoint.sh /entrypoint.sh
COPY baseline_activity.sh /opt/baseline_activity.sh
RUN chmod +x /entrypoint.sh /opt/baseline_activity.sh

EXPOSE 22 80

ENTRYPOINT ["/entrypoint.sh"]
