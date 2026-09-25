#!/usr/bin/env bash
set -euo pipefail

AGENT_LOG_DIR=${AGENT_LOG_DIR:-/var/log/agent-app}
LOG_FILE=${1:-$AGENT_LOG_DIR/monitor.log}
START_TIME=${2:-}
END_TIME=${3:-}

if [ ! -f "$LOG_FILE" ]; then
  echo "[ERROR] log file not found: $LOG_FILE"
  exit 1
fi

awk -v start="$START_TIME" -v end="$END_TIME" '
function valid_time(ts) {
  return (start == "" || ts >= start) && (end == "" || ts <= end)
}
function update(metric, value, ts) {
  count[metric]++
  sum[metric] += value
  if (!(metric in max) || value > max[metric]) { max[metric] = value; max_ts[metric] = ts }
  if (!(metric in min) || value < min[metric]) { min[metric] = value; min_ts[metric] = ts }
}
{
  ts = substr($0, 2, 19)
  if (!valid_time(ts)) next
  cpu = mem = disk = ""
  for (i = 1; i <= NF; i++) {
    if ($i ~ /^CPU:/) { cpu = $i; sub(/^CPU:/, "", cpu); sub(/%$/, "", cpu) }
    if ($i ~ /^MEM:/) { mem = $i; sub(/^MEM:/, "", mem); sub(/%$/, "", mem) }
    if ($i ~ /^DISK_USED:/) { disk = $i; sub(/^DISK_USED:/, "", disk); sub(/%$/, "", disk) }
  }
  if (cpu != "" && mem != "" && disk != "") {
    update("CPU", cpu + 0, ts)
    update("Memory", mem + 0, ts)
    update("Disk", disk + 0, ts)
    samples++
  }
}
END {
  print "====== STATISTICS REPORT ======"
  if (samples == 0) {
    print "[Samples]"
    print "Data Points: 0 samples"
    exit
  }
  metrics[1] = "CPU"; metrics[2] = "Memory"; metrics[3] = "Disk"
  for (i = 1; i <= 3; i++) {
    m = metrics[i]
    print "[" m "]"
    printf "Average : %.1f%%\n", sum[m] / count[m]
    printf "Maximum : %.1f%% at %s\n", max[m], max_ts[m]
    printf "Minimum : %.1f%% at %s\n", min[m], min_ts[m]
  }
  print "[Samples]"
  printf "Data Points: %d samples\n", samples
}' "$LOG_FILE"
