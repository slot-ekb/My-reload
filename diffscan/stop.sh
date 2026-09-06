#!/bin/bash
# Гасит только diffscan (по пути $BASE). Боевое/testgc/sweep не трогает.
BASE="$(cd "$(dirname "$0")"&&pwd)"; . "$BASE/config.env" 2>/dev/null; FP=${FAKE_PORT:-3799}
for s in $(screen -ls 2>/dev/null | grep -oE '[0-9]+\.ds_[0-9]+'); do screen -S "$s" -X quit 2>/dev/null; done
pkill -9 -f "$BASE/fakestratum.py $FP" 2>/dev/null
for pid in $(pgrep -x epic-miner-orig; pgrep -x epic-miner-range); do
  case "$(readlink /proc/$pid/cwd 2>/dev/null)" in "$BASE"/run/*) kill -9 "$pid" 2>/dev/null;; esac
done
echo "diffscan остановлен (боевое/testgc/sweep не тронуто)"
