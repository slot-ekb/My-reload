#!/bin/bash
# Гасит ТОЛЬКО процессы этого теста (по пути $BASE). Боевые майнеры/прокси НЕ трогает.
BASE="$(cd "$(dirname "$0")"&&pwd)"
# наши screen-сессии называются tw* / tg*
for s in $(screen -ls 2>/dev/null | grep -oE '[0-9]+\.(tw|tg)[0-9]+'); do screen -S "$s" -X quit 2>/dev/null; done
# процессы строго из папки теста (полный путь = боевое не совпадёт)
pkill -f "$BASE/bin/epic-miner-" 2>/dev/null
pkill -f "$BASE/bin/epic_proxy.py" 2>/dev/null
pkill -f "$BASE/fakestratum.py" 2>/dev/null
echo "тест остановлен (боевое не тронуто)"
