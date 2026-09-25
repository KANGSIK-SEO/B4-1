FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
       acl \
       cron \
       firewalld \
       iproute2 \
       openssh-server \
       procps \
       sudo \
       ufw \
       ca-certificates \
    && rm -rf /var/lib/apt/lists/*

ARG TARGETARCH

COPY app/agent-app-linux-x86 /opt/agent-src/agent-app-linux-x86
COPY app/agent-app-linux-arm64 /opt/agent-src/agent-app-linux-arm64
COPY scripts/entrypoint.sh /usr/local/sbin/agent-entrypoint.sh
COPY scripts/monitor.sh /opt/agent-src/monitor.sh
COPY scripts/report.sh /opt/agent-src/report.sh
COPY scripts/archive-agent-logs.sh /opt/agent-src/archive-agent-logs.sh

RUN chmod 755 /usr/local/sbin/agent-entrypoint.sh \
    && chmod 755 /opt/agent-src/agent-app-linux-x86 /opt/agent-src/agent-app-linux-arm64 \
    && chmod 755 /opt/agent-src/*.sh

EXPOSE 20022/tcp 15034/tcp

ENTRYPOINT ["/usr/local/sbin/agent-entrypoint.sh"]
