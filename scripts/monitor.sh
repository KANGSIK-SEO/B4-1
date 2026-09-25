#!/usr/bin/env bash
set -euo pipefail

AGENT_HOME=${AGENT_HOME:-/home/agent-admin/agent-app}
AGENT_PORT=${AGENT_PORT:-15034}
AGENT_LOG_DIR=${AGENT_LOG_DIR:-/var/log/agent-app}
APP_NAME=${APP_NAME:-agent-app}
LOG_FILE="$AGENT_LOG_DIR/monitor.log"
MAX_BYTES=$((10 * 1024 * 1024))
MAX_FILES=10

rotate_log_if_needed() {
  mkdir -p "$AGENT_LOG_DIR"
  [ -f "$LOG_FILE" ] || touch "$LOG_FILE"

  local size
  size=$(wc -c < "$LOG_FILE")
  if [ "$size" -le "$MAX_BYTES" ]; then
    return
  fi

  rm -f "$LOG_FILE.$MAX_FILES.gz"
  local i
  for ((i=MAX_FILES-1; i>=1; i--)); do
    if [ -f "$LOG_FILE.$i.gz" ]; then
      mv "$LOG_FILE.$i.gz" "$LOG_FILE.$((i + 1)).gz"
    fi
  done
  gzip -c "$LOG_FILE" > "$LOG_FILE.1.gz"
  : > "$LOG_FILE"
}

get_cpu_usage() {
  local first second idle1 total1 idle2 total2 idle_delta total_delta
  first=$(awk '/^cpu / {print $5, $2+$3+$4+$5+$6+$7+$8+$9+$10}' /proc/stat)
  sleep 0.2
  second=$(awk '/^cpu / {print $5, $2+$3+$4+$5+$6+$7+$8+$9+$10}' /proc/stat)
  read -r idle1 total1 <<< "$first"
  read -r idle2 total2 <<< "$second"
  idle_delta=$((idle2 - idle1))
  total_delta=$((total2 - total1))
  awk -v idle="$idle_delta" -v total="$total_delta" 'BEGIN {
    if (total <= 0) printf "0.0";
    else printf "%.1f", (1 - idle / total) * 100
  }'
}

get_mem_usage() {
  free | awk '/^Mem:/ {printf "%.1f", ($3 / $2) * 100}'
}

get_disk_used() {
  df -P / | awk 'NR==2 {gsub("%", "", $5); print $5}'
}

check_firewall() {
  if command -v ufw >/dev/null 2>&1; then
    if ufw status 2>/dev/null | grep -qi 'Status: active'; then
      echo "[OK] UFW active"
      return
    fi
    if [ -r /etc/ufw/ufw.conf ] && grep -Eq '^ENABLED=yes' /etc/ufw/ufw.conf; then
      echo "[OK] UFW active"
      return
    fi
  fi

  if command -v firewall-cmd >/dev/null 2>&1; then
    if firewall-cmd --state >/dev/null 2>&1; then
      echo "[OK] firewalld active"
      return
    fi
  fi

  echo "[WARNING] firewall is inactive or unavailable"
}

warn_if_gt() {
  local label=$1 value=$2 threshold=$3 unit=${4:-%}
  if awk -v v="$value" -v t="$threshold" 'BEGIN {exit !(v > t)}'; then
    printf '[WARNING] %s threshold exceeded (%s%s > %s%s)\n' "$label" "$value" "$unit" "$threshold" "$unit"
  fi
}

rotate_log_if_needed

PID=$(pgrep -u agent-admin -x "$APP_NAME" | head -n 1 || true)
if [ -z "$PID" ]; then
  PID=$(pgrep -u agent-admin -f "$AGENT_HOME/bin/$APP_NAME" | head -n 1 || true)
fi
if [ -z "$PID" ]; then
  echo "[ERROR] process '$APP_NAME' is not running"
  exit 1
fi

if ! ss -tuln | awk -v port=":$AGENT_PORT" '$1 == "tcp" && $5 ~ port "$" {found=1} END {exit !found}'; then
  echo "[ERROR] TCP $AGENT_PORT is not LISTEN"
  exit 1
fi

CPU_USAGE=$(get_cpu_usage)
MEM_USAGE=$(get_mem_usage)
DISK_USED=$(get_disk_used)
NOW=$(date '+%Y-%m-%d %H:%M:%S')

cat <<EOF
====== SYSTEM MONITOR RESULT ======

[HEALTH CHECK]
Checking process '$APP_NAME'... [OK] (PID: $PID)
Checking port $AGENT_PORT... [OK]
$(check_firewall)

[RESOURCE MONITORING]
CPU Usage : $CPU_USAGE%
MEM Usage : $MEM_USAGE%
DISK Used  : $DISK_USED%
EOF

warn_if_gt CPU "$CPU_USAGE" 20
warn_if_gt MEM "$MEM_USAGE" 10
warn_if_gt DISK_USED "$DISK_USED" 80

printf '[%s] PID:%s CPU:%s%% MEM:%s%% DISK_USED:%s%%\n' "$NOW" "$PID" "$CPU_USAGE" "$MEM_USAGE" "$DISK_USED" >> "$LOG_FILE"
printf '\n[INFO] Log appended: %s\n' "$LOG_FILE"
