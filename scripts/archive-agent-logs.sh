#!/usr/bin/env bash
set -euo pipefail

SOURCE_DIR=${AGENT_LOG_DIR:-/var/log/agent-app}
ARCHIVE_DIR=${ARCHIVE_DIR:-/var/log/monitor/agent-app/archive}

if [ ! -d "$SOURCE_DIR" ]; then
  echo "[WARNING] source directory does not exist: $SOURCE_DIR"
  exit 0
fi

mkdir -p "$ARCHIVE_DIR"

if [ ! -w "$ARCHIVE_DIR" ]; then
  echo "[WARNING] archive directory is not writable: $ARCHIVE_DIR"
  exit 0
fi

found=0
while IFS= read -r -d '' file; do
  found=1
  base=$(basename "$file")
  gzip -c "$file" > "$ARCHIVE_DIR/$base.gz"
  : > "$file"
  echo "[INFO] archived: $file -> $ARCHIVE_DIR/$base.gz"
done < <(find "$SOURCE_DIR" -maxdepth 1 -type f -name '*.log' -mtime +6 -print0)

if [ "$found" -eq 0 ]; then
  echo "[INFO] no log files older than 7 days"
fi

deleted=0
while IFS= read -r -d '' file; do
  deleted=1
  rm -f "$file"
  echo "[INFO] deleted old archive: $file"
done < <(find "$ARCHIVE_DIR" -type f -name '*.gz' -mtime +29 -print0)

if [ "$deleted" -eq 0 ]; then
  echo "[INFO] no archives older than 30 days"
fi
