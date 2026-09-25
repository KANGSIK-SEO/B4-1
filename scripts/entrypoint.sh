#!/usr/bin/env bash
set -euo pipefail

AGENT_HOME=${AGENT_HOME:-/home/agent-admin/agent-app}
AGENT_PORT=${AGENT_PORT:-15034}
AGENT_UPLOAD_DIR=${AGENT_UPLOAD_DIR:-$AGENT_HOME/upload_files}
AGENT_KEY_PATH=${AGENT_KEY_PATH:-$AGENT_HOME/api_keys}
AGENT_LOG_DIR=${AGENT_LOG_DIR:-/var/log/agent-app}

create_group() {
  local group_name=$1
  if ! getent group "$group_name" >/dev/null; then
    groupadd "$group_name"
  fi
}

create_user() {
  local user_name=$1
  if ! id "$user_name" >/dev/null 2>&1; then
    useradd -m -s /bin/bash "$user_name"
    echo "$user_name:agent1234!" | chpasswd
  fi
}

configure_sshd() {
  mkdir -p /run/sshd
  sed -i 's/^#\?Port .*/Port 20022/' /etc/ssh/sshd_config
  if grep -q '^#\?PermitRootLogin' /etc/ssh/sshd_config; then
    sed -i 's/^#\?PermitRootLogin .*/PermitRootLogin no/' /etc/ssh/sshd_config
  else
    printf '\nPermitRootLogin no\n' >> /etc/ssh/sshd_config
  fi
}

configure_firewall() {
  ufw --force reset >/dev/null 2>&1 || true
  ufw default deny incoming >/dev/null 2>&1 || true
  ufw default allow outgoing >/dev/null 2>&1 || true
  ufw allow 20022/tcp >/dev/null 2>&1 || true
  ufw allow 15034/tcp >/dev/null 2>&1 || true
  ufw --force enable >/dev/null 2>&1 || true
}

install_files() {
  local arch
  arch=$(uname -m)
  mkdir -p "$AGENT_HOME/bin" "$AGENT_UPLOAD_DIR" "$AGENT_KEY_PATH" "$AGENT_LOG_DIR" /var/log/monitor/agent-app/archive

  if [ "$arch" = "aarch64" ] || [ "$arch" = "arm64" ]; then
    cp /opt/agent-src/agent-app-linux-arm64 "$AGENT_HOME/bin/agent-app"
  else
    cp /opt/agent-src/agent-app-linux-x86 "$AGENT_HOME/bin/agent-app"
  fi

  cp /opt/agent-src/monitor.sh "$AGENT_HOME/bin/monitor.sh"
  cp /opt/agent-src/report.sh "$AGENT_HOME/bin/report.sh"
  cp /opt/agent-src/archive-agent-logs.sh "$AGENT_HOME/bin/archive-agent-logs.sh"
  printf 'agent_api_key_test\n' > "$AGENT_KEY_PATH/secret.key"
  printf 'agent_api_key_test\n' > "$AGENT_KEY_PATH/t_secret.key"

  chown -R agent-admin:agent-core "$AGENT_HOME" "$AGENT_LOG_DIR" /var/log/monitor/agent-app
  chown agent-dev:agent-core "$AGENT_HOME/bin/monitor.sh" "$AGENT_HOME/bin/report.sh" "$AGENT_HOME/bin/archive-agent-logs.sh"
  chmod 750 "$AGENT_HOME/bin/monitor.sh" "$AGENT_HOME/bin/report.sh" "$AGENT_HOME/bin/archive-agent-logs.sh"
  chmod 750 "$AGENT_HOME/bin/agent-app"

  chgrp agent-common "$AGENT_UPLOAD_DIR"
  chmod 2770 "$AGENT_UPLOAD_DIR"
  chgrp agent-core "$AGENT_KEY_PATH" "$AGENT_LOG_DIR"
  chmod 2770 "$AGENT_KEY_PATH" "$AGENT_LOG_DIR" /var/log/monitor/agent-app /var/log/monitor/agent-app/archive
  chmod 660 "$AGENT_KEY_PATH/secret.key" "$AGENT_KEY_PATH/t_secret.key"

  setfacl -m g:agent-common:rwx "$AGENT_UPLOAD_DIR"
  setfacl -d -m g:agent-common:rwx "$AGENT_UPLOAD_DIR"
  setfacl -m g:agent-core:rwx "$AGENT_KEY_PATH" "$AGENT_LOG_DIR"
  setfacl -d -m g:agent-core:rwx "$AGENT_KEY_PATH" "$AGENT_LOG_DIR"

  touch "$AGENT_LOG_DIR/monitor.log"
  chown agent-admin:agent-core "$AGENT_LOG_DIR/monitor.log"
  chmod 660 "$AGENT_LOG_DIR/monitor.log"
}

write_environment() {
  cat >/etc/profile.d/agent-app.sh <<EOF
export AGENT_HOME=$AGENT_HOME
export AGENT_PORT=$AGENT_PORT
export AGENT_UPLOAD_DIR=$AGENT_UPLOAD_DIR
export AGENT_KEY_PATH=$AGENT_KEY_PATH
export AGENT_LOG_DIR=$AGENT_LOG_DIR
EOF
  chmod 644 /etc/profile.d/agent-app.sh
}

configure_cron() {
  cat >/tmp/agent-admin-cron <<EOF
* * * * * . /etc/profile.d/agent-app.sh; $AGENT_HOME/bin/monitor.sh >> $AGENT_LOG_DIR/monitor-cron.out 2>&1
17 3 * * * . /etc/profile.d/agent-app.sh; $AGENT_HOME/bin/archive-agent-logs.sh >> $AGENT_LOG_DIR/archive-cron.out 2>&1
EOF
  crontab -u agent-admin /tmp/agent-admin-cron
  rm -f /tmp/agent-admin-cron
}

start_agent_app() {
  if pgrep -u agent-admin -f "$AGENT_HOME/bin/agent-app" >/dev/null; then
    return
  fi

  runuser -u agent-admin -- bash -lc "source /etc/profile.d/agent-app.sh; nohup '$AGENT_HOME/bin/agent-app' > '$AGENT_LOG_DIR/agent-app.stdout' 2>&1 &"
}

create_group agent-common
create_group agent-core
create_user agent-admin
create_user agent-dev
create_user agent-test
usermod -aG agent-common,agent-core agent-admin
usermod -aG agent-common,agent-core agent-dev
usermod -aG agent-common agent-test

configure_sshd
configure_firewall
install_files
write_environment
configure_cron

service ssh start >/dev/null
service cron start >/dev/null
start_agent_app

printf 'Agent monitor container is ready.\n'
printf 'SSH: docker exec -it <container> bash, or ssh -p 20022 agent-admin@localhost if port is published.\n'
printf 'App log: %s/agent-app.stdout\n' "$AGENT_LOG_DIR"

tail -F "$AGENT_LOG_DIR/agent-app.stdout" "$AGENT_LOG_DIR/monitor.log"
