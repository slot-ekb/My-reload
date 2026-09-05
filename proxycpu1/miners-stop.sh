#!/bin/bash
BASE="$(cd "$(dirname "$0")"&&pwd)"
for s in $(screen -ls 2>/dev/null | grep -oE 'wk[0-9]+'); do screen -S "$s" -X quit 2>/dev/null; done
screen -S logwatch-cpu -X quit 2>/dev/null
pkill -f "$BASE/bin/epic-miner" 2>/dev/null; echo "CPU-воркеры остановлены"
