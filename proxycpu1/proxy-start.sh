#!/bin/bash
BASE="$(cd "$(dirname "$0")"&&pwd)"; . "$BASE/config.env"; mkdir -p "$BASE/logs"
if [ "$PROXYLOG" = on ]; then DBG=debug; OUT="$BASE/logs/proxy.log"; else DBG=; OUT=/dev/null; fi
screen -S proxycpu-px -X quit 2>/dev/null; pkill -f "$BASE/bin/epic_proxy.py" 2>/dev/null; sleep 1
screen -dmS proxycpu-px bash -c "cd '$BASE'; while true; do python3 -u bin/epic_proxy.py $NODE $PROXY_PORT $DBG >> '$OUT' 2>&1; sleep 3; done"
sleep 1; ss -ltn 2>/dev/null | grep -q ":$PROXY_PORT " && echo "CPU-прокси OK :$PROXY_PORT (лог=$PROXYLOG)" || echo "CPU-прокси НЕ поднялся"
