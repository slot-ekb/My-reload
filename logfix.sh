#!/bin/bash
# Отключает файловые логи у всех майнер-инстансов, КРОМЕ инстанса 0 (ecuk0 / w0).
# Правит gen_toml в /opt/epic-cuckatoo/run.sh и heredoc в /opt/proxycu/start.sh. Идемпотентно.
python3 - <<'PY'
import os
# GPU: run.sh
r="/opt/epic-cuckatoo/run.sh"
if os.path.exists(r):
    s=open(r).read()
    old="    echo 'log_to_file = true'"
    new='    [ "$2" = 0 ] && echo \'log_to_file = true\' || echo \'log_to_file = false\''
    if old in s:
        open(r,"w").write(s.replace(old,new)); print("run.sh: пропатчен")
    elif "|| echo 'log_to_file = false'" in s:
        print("run.sh: уже пропатчен")
    else:
        print("run.sh: строку не нашёл — проверь вручную")
else:
    print("run.sh: нет файла (нет GPU-пакета?)")
# CPU: start.sh
f="/opt/proxycu/start.sh"
if os.path.exists(f):
    s=open(f).read()
    if "log_to_file = $LT" in s:
        print("start.sh: уже пропатчен")
    elif "log_to_file = true" in s and "for ((p=0;p<PROCS;p++)); do" in s:
        s=s.replace("log_to_file = true","log_to_file = $LT",1)
        s=s.replace("for ((p=0;p<PROCS;p++)); do",
                    'for ((p=0;p<PROCS;p++)); do\n  LT=$([ "$p" = 0 ] && echo true || echo false)',1)
        open(f,"w").write(s); print("start.sh: пропатчен")
    else:
        print("start.sh: строку не нашёл — проверь вручную")
else:
    print("start.sh: нет файла (нет CPU-пакета?)")
PY
echo "=== проверка ==="
grep -n 'log_to_file' /opt/epic-cuckatoo/run.sh 2>/dev/null
grep -n 'log_to_file\|LT=' /opt/proxycu/start.sh 2>/dev/null
echo "ГОТОВО. Теперь рестарт майнеров (run.sh gpu N / remine.sh) и чистка логов:"
echo "  rm -f /opt/epic-cuckatoo/instances/*/miner.log /opt/proxycu/inst/*/miner.log; : > /opt/proxygpu/logs/proxy.log 2>/dev/null"
