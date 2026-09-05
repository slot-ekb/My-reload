#!/bin/bash
# Запуск cpuwindow в screen "cpuwin" с авторестартом. Настройки — в config.env рядом.
BASE="$(cd "$(dirname "$0")"&&pwd)"; cd "$BASE"; . "$BASE/config.env"
SRC="${SRC:-127.0.0.1:3400}"; LEAD="${LEAD:-1}"; PERIOD="${PERIOD:-25}"; CUCKOO_MOD="${CUCKOO_MOD:-4}"
HOT="${HOT:-$BASE/cpumode.sh max}"; COLD="${COLD:-$BASE/cpumode.sh normal}"
export SRC LEAD PERIOD CUCKOO_MOD HOT COLD
screen -S cpuwin -X quit 2>/dev/null; pkill -f "$BASE/cpuwindow.py" 2>/dev/null; sleep 1
screen -dmS cpuwin bash -c "cd '$BASE'; export SRC='$SRC' LEAD='$LEAD' PERIOD='$PERIOD' CUCKOO_MOD='$CUCKOO_MOD' HOT='$HOT' COLD='$COLD'; while true; do python3 '$BASE/cpuwindow.py' >>'$BASE/cpuwindow.log' 2>&1; sleep 3; done"
sleep 1; echo "cpuwindow в screen \"cpuwin\": SRC=$SRC LEAD=$LEAD | лог: $BASE/cpuwindow.log"; tail -4 "$BASE/cpuwindow.log" 2>/dev/null
