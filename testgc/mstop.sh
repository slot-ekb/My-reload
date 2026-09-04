#!/bin/bash
# Без аргумента: гасит ВСЕ слоты теста. С SLOT=N: только слот N. Боевое (/opt) не трогает.
BASE="$(cd "$(dirname "$0")"&&pwd)"
for s in $(screen -ls 2>/dev/null | grep -oE '[0-9]+\.tm[0-9]+_[0-9]+'); do screen -S "$s" -X quit 2>/dev/null; done
pkill -9 -f "$BASE/bin/epic_proxy.py" 2>/dev/null
pkill -9 -f "$BASE/fakestratum.py" 2>/dev/null
# майнеры строго по cwd внутри тестовой папки
for pid in $(pgrep -x epic-miner-orig; pgrep -x epic-miner-range); do
  case "$(readlink /proc/$pid/cwd 2>/dev/null)" in "$BASE"/run/*) kill -9 "$pid" 2>/dev/null;; esac
done
echo "тест остановлен (все слоты); боевое /opt не тронуто"
