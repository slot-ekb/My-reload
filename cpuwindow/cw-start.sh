#!/bin/bash
# Запуск cpuwindow в screen "cpuwin" с авторестартом. Источник заданий определяется сам:
# локальный прокси (3400/3401) если поднят, иначе адрес ноды из конфига пакета.
BASE="$(cd "$(dirname "$0")"&&pwd)"; cd "$BASE"; . "$BASE/config.env" 2>/dev/null
LEAD="${LEAD:-1}"; PERIOD="${PERIOD:-25}"; CUCKOO_MOD="${CUCKOO_MOD:-4}"
HOT="${HOT:-$BASE/cpumode.sh max}"; COLD="${COLD:-$BASE/cpumode.sh normal}"
if [ -z "$SRC" ] || [ "$SRC" = auto ]; then
  if ss -ltn 2>/dev/null | grep -q ':3400 '; then SRC=127.0.0.1:3400
  elif ss -ltn 2>/dev/null | grep -q ':3401 '; then SRC=127.0.0.1:3401
  else SRC=$(grep -hoE '^NODE="[^"]+"' /opt/proxycpu1/config.env /opt/proxygpu1/config.env 2>/dev/null | head -1 | sed -E 's/NODE="([^"]+)"/\1/'); fi
fi
[ -z "$SRC" ] && SRC=127.0.0.1:3400
export SRC LEAD PERIOD CUCKOO_MOD HOT COLD
screen -S cpuwin -X quit 2>/dev/null; pkill -f "$BASE/cpuwindow.py" 2>/dev/null; sleep 1
screen -dmS cpuwin bash -c "cd '$BASE'; export SRC='$SRC' LEAD='$LEAD' PERIOD='$PERIOD' CUCKOO_MOD='$CUCKOO_MOD' HOT='$HOT' COLD='$COLD'; while true; do python3 '$BASE/cpuwindow.py' >>'$BASE/cpuwindow.log' 2>&1; sleep 3; done"
sleep 1; echo "cpuwindow в screen \"cpuwin\": SRC=$SRC LEAD=$LEAD | screen -r cpuwin | лог: $BASE/cpuwindow.log"; tail -5 "$BASE/cpuwindow.log" 2>/dev/null
