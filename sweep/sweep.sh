#!/bin/bash
# sweep — для ОДНОГО солвера подбирает лучшее число потоков (nthreads).
# Для каждого N из THREADS: гоняет 1 процесс × 1 инстанс × N потоков на N физ.ядрах
# и (если COMPARE=on) для сравнения — N солверов × 1 поток на тех же N ядрах.
# Метрика — ШАР/СЕК (реальная мощь), плюс g/s. Всё на своём фейк-стенде; боевое не трогает.
#   ./sweep.sh [секунд] ["список потоков"] [бинарь]
#   ./sweep.sh 40 "1 2 4 6 8"
BASE="$(cd "$(dirname "$0")"&&pwd)"; cd "$BASE"; . "$BASE/config.env"
SECS=${1:-${SECS:-40}}
LIST=${2:-${THREADS:-"1 2 4 6 8"}}
BIN=${3:-${BIN:-orig}}
. "$BASE/corelist.sh"                       # CORES[] (физ.ядра как "0,28"), NCORE
MB="$BASE/bin/epic-miner-${BIN}"
FP=$FAKE_PORT; CP=$PROXY_PORT
RUN="$BASE/run"; FLOG="$BASE/fake.log"; PLOG="$BASE/proxy.log"

killall_(){
  for s in $(screen -ls 2>/dev/null | grep -oE '[0-9]+\.sw_[0-9]+'); do screen -S "$s" -X quit 2>/dev/null; done
  pkill -9 -f "epic_proxy.py 127.0.0.1:$FP " 2>/dev/null
  pkill -9 -f "fakestratum.py $FP" 2>/dev/null
  for pid in $(pgrep -x epic-miner-orig; pgrep -x epic-miner-range); do
    case "$(readlink /proc/$pid/cwd 2>/dev/null)" in "$RUN"/*) kill -9 "$pid" 2>/dev/null;; esac
  done
}
trap 'killall_; exit 0' INT TERM

# один замер: $1=число процессов $2=nthreads $3=меток-ядер(всего). Печатает "gps sps".
measure(){
  local NP=$1 NTH=$2 NC=$3
  killall_; sleep 1; rm -rf "$RUN"; mkdir -p "$RUN"
  setsid python3 "$BASE/fakestratum.py" "$FP" >"$FLOG" 2>&1 & sleep 1
  setsid python3 -u "$BASE/bin/epic_proxy.py" "127.0.0.1:$FP" "$CP" >"$PLOG" 2>&1 & sleep 2
  local ci=0 p
  for ((p=0;p<NP;p++)); do
    local D="$RUN/w$p"; mkdir -p "$D"
    { echo '[logging]'; echo 'log_to_stdout = false'; echo 'log_to_file = true'
      echo 'file_log_level = "Info"'; echo 'stdout_log_level = "Info"'
      echo "log_file_path = \"$D/miner.log\""; echo 'log_file_append = false'
      echo '[mining]'; echo 'algorithm = "Cuckoo"'; echo 'run_tui = false'
      echo "stratum_server_addr = \"127.0.0.1:$CP\""; echo 'stratum_server_tls_enabled = false'
      echo "miner_plugin_dir = \"$BASE/plugins\""
      echo '[mining.randomx_config]'; echo 'threads = 1'; echo 'jit = true'; echo 'large_pages = false'; echo 'hard_aes = true'
      echo '[[mining.gpu_config]]'; echo 'device = 0'; echo 'driver = 2'
      echo '[[mining.miner_plugin_config]]'; echo 'plugin_name = "cuckatoo_mean_cpu_avx2_19"'
      echo '[mining.miner_plugin_config.parameters]'; echo "nthreads = $NTH"
    } > "$D/epic-miner.toml"
    # этому процессу — NTH физ.ядер подряд из общего пула NC
    local sl="" q
    for ((q=0;q<NTH;q++)); do [ -n "${CORES[$ci]}" ] && sl+="${CORES[$ci]},"; ci=$((ci+1)); done; sl=${sl%,}
    local TASK=""; [ -n "$sl" ] && TASK="taskset -c $sl "
    screen -dmS "sw_$p" bash -c "cd '$D'; export LD_LIBRARY_PATH='$BASE/lib'; export EPIC_RANGE='${RANGE:-1}'; while true; do ${TASK}'$MB' -c epic-miner.toml; sleep 3; done"
  done
  sleep "$SECS"
  local g=0 v f
  for f in "$RUN"/*/miner.log; do [ -f "$f" ] || continue; v=$(grep -oE 'at [0-9.]+ gps' "$f" 2>/dev/null|tail -1|grep -oE '[0-9.]+'); [ -n "$v" ] && g=$(awk "BEGIN{printf \"%.1f\",$g+$v}"); done
  local tx; tx=$(grep 'СТАТ' "$PLOG"|tail -1|grep -oE 'шары_отосл=[0-9]+'|grep -oE '[0-9]+$'); tx=${tx:-0}
  local sps; sps=$(awk "BEGIN{printf \"%.2f\",$tx/$SECS}")
  killall_
  echo "$g $sps"
}

echo "=========================================================="
echo " sweep: сколько ПОТОКОВ лучше в ОДНОМ солвере (бинарь=$BIN, ${SECS}с/замер)"
echo " физ.ядер на машине: $NCORE | перебор потоков: $LIST"
echo "=========================================================="
printf "%-8s | %-22s | %-22s\n" "потоков" "1 солвер×N потоков" "$([ "$COMPARE" = on ] && echo "N солверов×1 поток" || echo "")"
printf "%-8s | %-10s %-10s | %-10s %-10s\n" "(=ядер)" "g/s" "шар/с" "g/s" "шар/с"
echo "----------------------------------------------------------------------"
for N in $LIST; do
  [ "$N" -gt "$NCORE" ] && { echo "  $N потоков > $NCORE ядер — пропуск"; continue; }
  read A_G A_S <<< "$(measure 1 "$N" "$N")"                       # 1 солвер, N потоков
  if [ "$COMPARE" = on ]; then read B_G B_S <<< "$(measure "$N" 1 "$N")"; else B_G="-"; B_S="-"; fi
  printf "%-8s | %-10s %-10s | %-10s %-10s\n" "$N" "$A_G" "$A_S" "$B_G" "$B_S"
done
echo "----------------------------------------------------------------------"
echo "Смотри ШАР/С. Слева — потоки в одном солвере; справа — те же ядра как отдельные солверы."
echo "Обычно на cuckatoo правый столбец растёт линейнее (независимые солверы),"
echo "а потоки в одном солвере масштабируются хуже. Где левый перестал расти — там потолок nthreads."
