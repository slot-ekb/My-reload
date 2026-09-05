#!/bin/bash
BASE="$(cd "$(dirname "$0")"&&pwd)"; . "$BASE/config.env"
LOG="$1"; MAX=$(( ${LOG_MAX_MB:-100} * 1024 * 1024 ))
while true; do
  [ -f "$LOG" ] && [ "$(stat -c%s "$LOG" 2>/dev/null||echo 0)" -gt "$MAX" ] && : > "$LOG"
  sleep 300
done
