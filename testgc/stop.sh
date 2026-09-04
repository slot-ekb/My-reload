#!/bin/bash
# Гасит ВСЁ, что поднимали тесты: майнеры, прокси, фейк-ноду.
BASE="$(cd "$(dirname "$0")"&&pwd)"; . "$BASE/config.env" 2>/dev/null
for s in $(screen -ls 2>/dev/null | grep -oE '[0-9]+\.(tw|tg)[0-9a-z]*' ); do screen -S "$s" -X quit 2>/dev/null; done
pkill -f "epic-miner-(orig|range) -c epic-miner.toml" 2>/dev/null
pkill -f "epic_proxy.py 127.0.0.1:${FAKE_PORT:-3499}" 2>/dev/null
pkill -f "fakestratum.py" 2>/dev/null
echo "всё остановлено (майнеры + прокси + фейк-нода)"
