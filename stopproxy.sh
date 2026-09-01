#!/bin/bash
# Остановить ТОЛЬКО прокси proxycu. Майнеры (pcu*) не трогаем.
cd "$(dirname "$0")"; BASE="$(pwd)"
pkill -f "$BASE/bin/epic_proxy.py" 2>/dev/null
screen -S proxycu-px -X quit 2>/dev/null
sleep 1
if pgrep -f "$BASE/bin/epic_proxy.py" >/dev/null; then
  echo "прокси всё ещё жив — повтори команду"
else
  echo "прокси остановлен (майнеры не тронуты)"
fi
