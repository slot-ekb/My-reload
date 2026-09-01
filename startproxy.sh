#!/bin/bash
# Запустить ТОЛЬКО прокси proxycu. Майнеры не трогаем.
cd "$(dirname "$0")"; BASE="$(pwd)"; . ./config.env
mkdir -p logs
if [ "$NODE" = "ВПИШИ_IP:3416" ] || [ -z "$NODE" ]; then
  echo "!!! Впиши адрес ноды в config.env (NODE=\"IP:порт\")"; exit 1
fi
if pgrep -f "$BASE/bin/epic_proxy.py" >/dev/null; then
  echo "прокси уже работает — сначала ./stopproxy.sh"; exit 0
fi
screen -dmS proxycu-px bash -c "cd '$BASE'; python3 -u bin/epic_proxy.py $NODE $PROXY_PORT >> logs/proxy.log 2>&1"
sleep 2
if pgrep -f "$BASE/bin/epic_proxy.py" >/dev/null; then
  echo "прокси поднят: -> $NODE, слушает :$PROXY_PORT"
else
  echo "прокси НЕ стартовал:"; tail -5 logs/proxy.log
fi
