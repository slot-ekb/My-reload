#!/bin/bash
# Живая таблица прокси: ./proxydash.sh [ЛОКАЛ_ПОРТ] [НОДА_ПОРТ]
PORT="${1:-3400}"; NPORT="${2:-3416}"
watch -t -n2 "
echo '========= EPIC PROXY ($(hostname)) ========='
pgrep -f epic_proxy.py >/dev/null && echo ' статус         : РАБОТАЕТ' || echo ' статус         : *** СТОП ***'
printf ' воркеров->прокси: %s\n' \$(ss -Htn state established '( dport = :$PORT )' 2>/dev/null | wc -l)
printf ' прокси->нода    : %s\n' \$(ss -Htn state established '( dport = :$NPORT )' 2>/dev/null | wc -l)
printf ' заданий получено: %s\n' \$(grep -c '\"method\":\"job\"' /tmp/proxy.log 2>/dev/null)
echo
echo ' --- текущее задание ---'
L=\$(grep '\"method\":\"job\"' /tmp/proxy.log 2>/dev/null | tail -1)
echo \"\$L\" | grep -oE '\"algorithm\":\"[a-z]+\"' | sed 's/^/ алгоритм: /'
echo \"\$L\" | grep -oE '\\[\"cuckoo\",[0-9]+\\]' | head -1 | sed 's/^/ порог cuckoo: /'
echo
echo ' --- лог (хвост) ---'
tail -3 /tmp/proxy.log 2>/dev/null | cut -c1-100
"
