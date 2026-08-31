#!/bin/bash
# Управление прокси: ./proxyctl.sh start|stop|status|log  [НОДА:ПОРТ] [ЛОКАЛ_ПОРТ]
cd "$(dirname "$0")"; D="$(pwd)"
NODE="${2:-212.220.216.27:3416}"; PORT="${3:-3400}"
NPORT="${NODE##*:}"
case "$1" in
  start)
    pkill -f epic_proxy.py 2>/dev/null; screen -S proxy -X quit 2>/dev/null; sleep 1
    screen -dmS proxy bash -c "cd '$D'; python3 -u epic_proxy.py $NODE $PORT > /tmp/proxy.log 2>&1"
    sleep 2
    if pgrep -f epic_proxy.py >/dev/null; then echo "ПРОКСИ запущен: воркеры -> :$PORT | нода -> $NODE"; else echo "НЕ стартовал, смотри /tmp/proxy.log"; tail -5 /tmp/proxy.log; fi ;;
  stop)
    pkill -f epic_proxy.py 2>/dev/null; screen -S proxy -X quit 2>/dev/null; echo "ПРОКСИ остановлен" ;;
  status)
    pgrep -f epic_proxy.py >/dev/null && echo "статус: РАБОТАЕТ" || echo "статус: СТОП"
    echo "воркеров на прокси: $(ss -Htn state established "( dport = :$PORT )" 2>/dev/null | wc -l)"
    echo "коннект к ноде:     $(ss -Htn state established "( dport = :$NPORT )" 2>/dev/null | wc -l)"
    echo "--- лог ---"; tail -3 /tmp/proxy.log 2>/dev/null | cut -c1-120 ;;
  log) tail -f /tmp/proxy.log ;;
  *) echo "usage: ./proxyctl.sh start|stop|status|log  [НОДА:ПОРТ] [ЛОКАЛ_ПОРТ]" ;;
esac
