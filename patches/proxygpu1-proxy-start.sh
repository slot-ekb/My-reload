#!/bin/bash
BASE="$(cd "$(dirname "$0")"&&pwd)"; . "$BASE/config.env"; mkdir -p "$BASE/logs"
if [ "$PROXYLOG" = on ]; then DBG=debug; OUT="$BASE/logs/proxy.log"; else DBG=; OUT=/dev/null; fi
NODES="$NODE"; [ -n "$NODE2" ] && NODES="$NODE,$NODE2"   # NODE2 = дубль/резерв (ТА ЖЕ цепь!)
screen -S proxygpu-px -X quit 2>/dev/null; pkill -f "$BASE/bin/epic_proxy.py" 2>/dev/null; sleep 1
screen -dmS proxygpu-px bash -c "cd '$BASE'; while true; do python3 -u bin/epic_proxy.py '$NODES' $PROXY_PORT $DBG >> '$OUT' 2>&1; sleep 3; done"
sleep 1; ss -ltn 2>/dev/null | grep -q ":$PROXY_PORT " && echo "GPU-прокси OK :$PROXY_PORT ноды=[$NODES] (лог=$PROXYLOG)" || echo "GPU-прокси НЕ поднялся"
