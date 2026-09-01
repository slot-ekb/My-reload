#!/bin/bash
# Диагностика Epic-ноды: пиры, коннекты по портам, признаки DDoS.
# Запускать НА НОДЕ. Использование: bash nodediag.sh
echo "================ NODE DIAG  $(hostname)  $(date '+%F %T') ================"
echo "--- нагрузка ---"; uptime

echo; echo "--- слушающие порты ноды (P2P/стратум/API) ---"
ss -tlnp 2>/dev/null | grep -iE 'epic|403p340|:341[0-9]|:2806[0-9]|:3416' | awk '{print $4, $6}'

# авто-детект бинаря ноды
NODEBIN=$(ls -l /proc/$(pgrep -f 'epic|403p340' | head -1)/exe 2>/dev/null | grep -oE '/[^ ]+$')

echo; echo "--- коннекты по ключевым портам ---"
for P in 3414 3415 3416 28061; do
  est=$(ss -Htn state established "( sport = :$P or dport = :$P )" 2>/dev/null | wc -l)
  syn=$(ss -Htn state syn-recv "( sport = :$P )" 2>/dev/null | wc -l)
  tw=$(ss -Htn state time-wait "( sport = :$P )" 2>/dev/null | wc -l)
  [ "$est" -gt 0 -o "$syn" -gt 0 ] && echo "порт $P: established=$est  SYN-RECV=$syn(<-флуд если много)  TIME-WAIT=$tw"
done

echo; echo "--- ТОП удалённых IP по числу коннектов (кандидаты на DDoS) ---"
ss -Htn state established 2>/dev/null | awk '{print $4}' | sed -E 's/:[0-9]+$//' | sort | uniq -c | sort -rn | head -15

echo; echo "--- всего отслеживаемых соединений (conntrack) ---"
c=$(cat /proc/sys/net/netfilter/nf_conntrack_count 2>/dev/null); m=$(cat /proc/sys/net/netfilter/nf_conntrack_max 2>/dev/null)
echo "conntrack: $c / $m"

echo; echo "--- трафик по интерфейсам за 2с (rx/tx КБ/с) ---"
read -r a < <(awk -F'[: ]+' '/:/{if($2>0||$10>0)print $1" "$3" "$11}' /proc/net/dev | grep -vE '^lo')
snap(){ awk -F'[: ]+' '/:/{print $1" "$3" "$11}' /proc/net/dev | grep -vE '^lo '; }
s1=$(snap); sleep 2; s2=$(snap)
join <(echo "$s1") <(echo "$s2") 2>/dev/null | awk '{printf "  %s: rx=%.0f КБ/с tx=%.0f КБ/с\n",$1,($4-$2)/2/1024,($5-$3)/2/1024}'

if [ -n "$NODEBIN" ]; then
  echo; echo "--- epic client status ---"; timeout 8 "$NODEBIN" client status 2>/dev/null | head -12
  echo; echo "--- подключённые пиры ---"; timeout 8 "$NODEBIN" client listconnectedpeers 2>/dev/null | tail -30
fi
echo "================ КОНЕЦ ================"
