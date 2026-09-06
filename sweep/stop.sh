#!/bin/bash
# Гасит только процессы sweep (по пути $BASE). Боевое/testgc не трогает.
BASE="$(cd "$(dirname "$0")"&&pwd)"; . "$BASE/config.env" 2>/dev/null; FP=${FAKE_PORT:-3699}
for s in $(screen -ls 2>/dev/null | grep -oE '[0-9]+\.sw_[0-9]+'); do screen -S "$s" -X quit 2>/dev/null; done
pkill -9 -f "epic_proxy.py 127.0.0.1:$FP " 2>/dev/null
pkill -9 -f "fakestratum.py $FP" 2>/dev/null
for pid in $(pgrep -x epic-miner-orig; pgrep -x epic-miner-range); do
  case "$(readlink /proc/$pid/cwd 2>/dev/null)" in "$BASE"/run/*) kill -9 "$pid" 2>/dev/null;; esac
done
echo "sweep остановлен (боевое/testgc не тронуто)"
