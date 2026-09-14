FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    nmap \
    curl \
    hydra \
    openssh-client \
    iputils-ping \
    netcat-traditional \
    && rm -rf /var/lib/apt/lists/*

COPY scripts/ /opt/scripts/
RUN chmod +x /opt/scripts/*.sh

WORKDIR /opt/scripts
CMD ["sleep", "infinity"]
