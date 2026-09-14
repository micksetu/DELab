FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    openssh-server \
    sudo \
    cron \
    rsyslog \
    python3 \
    iputils-ping \
    net-tools \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /var/run/sshd

COPY entrypoint.sh /entrypoint.sh
COPY baseline_activity.sh /opt/baseline_activity.sh
RUN chmod +x /entrypoint.sh /opt/baseline_activity.sh

EXPOSE 22 80

ENTRYPOINT ["/entrypoint.sh"]
