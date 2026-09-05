#!/bin/bash
BASE="$(cd "$(dirname "$0")"&&pwd)"
screen -S proxycpu-px -X quit 2>/dev/null; pkill -f "$BASE/bin/epic_proxy.py" 2>/dev/null; echo "CPU-прокси остановлен"
