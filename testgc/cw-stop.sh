#!/bin/bash
# Стоп cpuwindow + вернуть normal.
BASE="$(cd "$(dirname "$0")"&&pwd)"
screen -S cpuwin -X quit 2>/dev/null; pkill -f "$BASE/cpuwindow.py" 2>/dev/null; sleep 1
"$BASE/cpumode.sh" normal >/dev/null 2>&1
echo "cpuwindow остановлен, CPU возвращён в normal"
