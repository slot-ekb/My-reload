#!/bin/bash
# Диагностика Epic-ноды: пиры, коннекты, признаки DDoS. РАБОТАЕТ НА ЛЮБОЙ НОДЕ (автоопределение).
# Запуск на ноде: bash nodediag.sh            (авто)
#                 bash nodediag.sh <pid|имя>  (если авто не нашёл)
echo "================ NODE DIAG  $(hostname)  $(date '+%F %T') ================"
uptime

# --- найти PID ноды ---
ARG="$1"
if [ -n "$ARG" ] && [[ "$ARG" =~ ^[0-9]+$ ]]; then NODEPID="$ARG"
elif [ -n "$ARG" ]; then NODEPID=$(pgrep -f "$ARG" | head -1)
else
  NODEPID=$(pgrep -f 'epic|403p340' | head -1)
  # запасной способ: процесс с наибольшим числом установленных TCP-коннектов
  [ -z "$NODEPID" ] && NODEPID=$(ss -Htnp state established 2>/dev/null | grep -oE 'pid=[0-9]+' | sort | uniq -c | sort -rn | head -1 | grep -oE '[0-9]+$')
fi
if [ -z "$NODEPID" ] || [ ! -d "/proc/$NODEPID" ]; then
  echo "!!! процесс ноды не найден. Запусти: bash nodediag.sh <pid|имя_бинаря>"; NODEPID=""
fi
NODEBIN=$(readlink -f /proc/$NODEPID/exe 2>/dev/null)
NODECWD=$(readlink -f /proc/$NODEPID/cwd 2>/dev/null)
echo; echo "нода: pid=$NODEPID bin=$NODEBIN cwd=$NODECWD"

# --- слушающие порты именно этого процесса ---
PORTS=$(ss -Htlnp 2>/dev/null | grep "pid=$NODEPID," | grep -oE ':[0-9]+ ' | tr -d ': ' | sort -un)
echo; echo "--- порты ноды (слушает) ---"; echo "$PORTS" | tr '\n' ' '; echo

# --- коннекты по каждому порту ноды ---
echo; echo "--- коннекты по портам ноды ---"
for P in $PORTS; do
  est=$(ss -Htn state established "( sport = :$P )" 2>/dev/null | wc -l)
  syn=$(ss -Htn state syn-recv "( sport = :$P )" 2>/dev/null | wc -l)
  tw=$(ss -Htn state time-wait "( sport = :$P )" 2>/dev/null | wc -l)
  echo "порт $P: established=$est  SYN-RECV=$syn(<-флуд если много)  TIME-WAIT=$tw"
done

echo; echo "--- ТОП удалённых IP по числу коннектов (кандидаты на DDoS) ---"
ss -Htn state established 2>/dev/null | awk '{print $4}' | sed -E 's/:[0-9]+$//' | sort | uniq -c | sort -rn | head -15

echo; echo "--- conntrack (всего отслеживается) ---"
echo "$(cat /proc/sys/net/netfilter/nf_conntrack_count 2>/dev/null) / $(cat /proc/sys/net/netfilter/nf_conntrack_max 2>/dev/null)"

echo; echo "--- трафик по интерфейсам за 2с (КБ/с) ---"
snap(){ awk -F'[: ]+' '/:/{print $1" "$3" "$11}' /proc/net/dev | grep -vE '^lo '; }
s1=$(snap); sleep 2; s2=$(snap)
join <(echo "$s1") <(echo "$s2") 2>/dev/null | awk '{r=($4-$2)/2/1024; t=($5-$3)/2/1024; if(r>0||t>0)printf "  %s: rx=%.0f tx=%.0f КБ/с\n",$1,r,t}'

# --- epic client (из каталога конфига ноды) ---
if [ -n "$NODEBIN" ] && [ -n "$NODECWD" ]; then
  echo; echo "--- epic client status ---"; (cd "$NODECWD" && timeout 8 "$NODEBIN" client status 2>/dev/null | head -12)
  echo; echo "--- подключённые пиры ---"; (cd "$NODECWD" && timeout 8 "$NODEBIN" client listconnectedpeers 2>/dev/null | tail -30)
fi
echo "================ КОНЕЦ ================"
