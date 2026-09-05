#!/bin/bash
# USE_PROXY=on  -> поднять прокси, майнеры идут через него (127.0.0.1:PROXY_PORT)
# USE_PROXY=off -> без прокси, майнеры прямо на NODE
BASE="$(cd "$(dirname "$0")"&&pwd)"; . "$BASE/config.env"
if [ "${USE_PROXY:-off}" = on ]; then "$BASE/proxy-start.sh"; sleep 2; fi
"$BASE/miners-start.sh"
