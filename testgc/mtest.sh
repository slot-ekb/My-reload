#!/bin/bash
# Замер g/s + шары на фейк-ноде. Параллельные окна = разные SLOT (свои порты/файлы).
#   ./mtest.sh cpu [экземпляров] [инстансов] [ядер] [секунд] [nthreads] [бинарь]
#   ./mtest.sh gpu [экземпляров] [инстансов] [карт] [секунд] [бинарь]
# Параллельно в разных окнах:  SLOT=1 ./mtest.sh ... | SLOT=2 ./mtest.sh ...
# Конкретные карты:            GPU_DEVICES=1,3 ./mtest.sh gpu ...
BASE="$(cd "$(dirname "$0")"&&pwd)"
_ENVRANGE="${RANGE:-}"; _ENVMINER="${MINER:-}"        # env-префикс главнее config.env
. "$BASE/config.env"
[ -n "$_ENVRANGE" ] && RANGE="$_ENVRANGE"
[ -n "$_ENVMINER" ] && MINER="$_ENVMINER"
MODE=${1:-cpu}
EXE=${2:-1};  [ "$EXE" -lt 1 ] && EXE=1
INST=${3:-1}; [ "$INST" -lt 1 ] && INST=1
NUM=${4:-2}
SECS=${5:-20}
SLOT=${SLOT:-0}
export LD_LIBRARY_PATH="$BASE/lib"; export EPIC_RANGE="${RANGE:-1}"
FP=$(( FAKE_PORT + SLOT*10 ))
RUN="$BASE/run/s$SLOT"; FLOG="$BASE/fake_s$SLOT.log"; PLOG="$BASE/proxy_s$SLOT.log"

# --- уборка ТОЛЬКО своего слота ---
slotstop(){
  for s in $(screen -ls 2>/dev/null | grep -oE "[0-9]+\.tm${SLOT}_[0-9]+"); do screen -S "$s" -X quit 2>/dev/null; done
  pkill -9 -f "epic_proxy.py 127.0.0.1:$FP " 2>/dev/null
  pkill -9 -f "fakestratum.py $FP" 2>/dev/null
  for pid in $(pgrep -x epic-miner-orig; pgrep -x epic-miner-range); do
    case "$(readlink /proc/$pid/cwd 2>/dev/null)" in "$RUN"/*) kill -9 "$pid" 2>/dev/null;; esac
  done
}
slotstop; sleep 1; rm -rf "$RUN"

if [ "$MODE" = gpu ]; then
  NTH=1; BIN=${6:-${BIN:-orig}}; CP=$(( GPU_PROXY_PORT + SLOT*10 )); PLUG=cuckatoo_lean_cuda_19
  NG=$(nvidia-smi -L 2>/dev/null | wc -l); [ "$NG" -lt 1 ] && NG=1
  [ "$NUM" -le 0 ] && NUM=$NG; [ "$NUM" -gt "$NG" ] && NUM=$NG
  if [ -n "$GPU_DEVICES" ]; then IFS=',' read -ra DEVS <<< "$GPU_DEVICES"; NUM=${#DEVS[@]}; else DEVS=(); for ((c=0;c<NUM;c++)); do DEVS+=("$c"); done; fi
else
  MODE=cpu; NTH=${6:-1}; BIN=${7:-${BIN:-orig}}; CP=$(( CPU_PROXY_PORT + SLOT*10 )); PLUG=cuckatoo_mean_cpu_avx2_19
  [ "$NUM" -lt 1 ] && NUM=1
  . "$BASE/corelist.sh"; PERPROC=$(( INST * NTH ))   # как в бою: пин по физ.ядрам с ядра 0
fi
MB="$BASE/bin/epic-miner-${BIN}"

ROTATE_JOB="${ROTATE_JOB:-0}" setsid python3 "$BASE/fakestratum.py" "$FP" >"$FLOG" 2>&1 & sleep 1
setsid python3 -u "$BASE/bin/epic_proxy.py" "127.0.0.1:$FP" "$CP" >"$PLOG" 2>&1 & sleep 2

STEP=$(( NUM / EXE )); [ "$STEP" -lt 1 ] && STEP=1
if [ "$MODE" = cpu ]; then HW="физ.ядер=$(( EXE*PERPROC )) (по $PERPROC/экз, nthreads=$NTH; 4-й арг игнор — пин как в бою)"; else HW="карты=[${DEVS[*]}]${GPU_PIN:+ пин-ядро=$GPU_PIN}"; fi
echo ">>> [SLOT $SLOT порты $FP/$CP] $MODE: экземпляров=$EXE инстансов=$INST $HW бинарь=$BIN замер ${SECS}с..."

for ((e=0;e<EXE;e++)); do
  D="$RUN/e$e"; mkdir -p "$D"
  {
  echo '[logging]'; echo 'log_to_stdout = false'; echo 'log_to_file = true'
  echo 'file_log_level = "Info"'; echo 'stdout_log_level = "Info"'
  echo "log_file_path = \"$D/miner.log\""; echo 'log_file_append = false'
  echo '[mining]'; echo 'algorithm = "Cuckoo"'; echo 'run_tui = false'
  echo "stratum_server_addr = \"127.0.0.1:$CP\""; echo 'stratum_server_tls_enabled = false'
  echo "miner_plugin_dir = \"$BASE/plugins\""
  echo '[mining.randomx_config]'; echo 'threads = 1'; echo 'jit = true'; echo 'large_pages = false'; echo 'hard_aes = true'
  if [ "$MODE" = gpu ]; then
    for d in "${DEVS[@]}"; do echo '[[mining.gpu_config]]'; echo "device = $d"; echo 'driver = 2'; done
    for d in "${DEVS[@]}"; do for ((k=0;k<INST;k++)); do
      echo '[[mining.miner_plugin_config]]'; echo "plugin_name = \"$PLUG\""
      echo '[mining.miner_plugin_config.parameters]'; echo "device = $d"; done; done
  else
    echo '[[mining.gpu_config]]'; echo 'device = 0'; echo 'driver = 2'
    for ((k=0;k<INST;k++)); do
      echo '[[mining.miner_plugin_config]]'; echo "plugin_name = \"$PLUG\""
      echo '[mining.miner_plugin_config.parameters]'; echo "nthreads = $NTH"; done
  fi
  } > "$D/epic-miner.toml"
  if [ "$MODE" = cpu ]; then sl=""; for ((q=0;q<PERPROC;q++)); do ci=$((e*PERPROC+q)); [ -n "${CORES[$ci]}" ] && sl+="${CORES[$ci]},"; done; sl=${sl%,}; PIN=""; [ -n "$sl" ] && PIN="taskset -c $sl ";
  elif [ -n "$GPU_PIN" ]; then PIN="taskset -c $GPU_PIN "; else PIN=""; fi
  screen -dmS "tm${SLOT}_$e" bash -c "cd '$D'; export LD_LIBRARY_PATH='$BASE/lib'; export EPIC_RANGE='${RANGE:-1}'; while true; do ${PIN}'$MB' -c epic-miner.toml; sleep 3; done"
done

sumgps(){ local s=0 v f; for f in "$RUN"/*/miner.log; do [ -f "$f" ] || continue; v=$(grep -oE 'at [0-9.]+ gps' "$f" 2>/dev/null|tail -1|grep -oE '[0-9.]+'); [ -n "$v" ] && s=$(awk "BEGIN{printf \"%.1f\",$s+$v}"); done; echo "$s"; }
getk(){ grep 'СТАТ' "$PLOG"|tail -1|grep -oE "$1=[0-9]+"|grep -oE '[0-9]+$'; }
getf(){ grep 'НОДА СТАТ' "$FLOG"|tail -1|grep -oE "$1=[0-9]+"|grep -oE '[0-9]+$'; }
el=0; step=5
while [ "$el" -lt "$SECS" ]; do sl=$step; [ $((el+step)) -gt "$SECS" ] && sl=$((SECS-el)); sleep "$sl"; el=$((el+sl))
  printf "  [SLOT %s] [%2s/%sс] g/s=%-9s шары=%-5s\n" "$SLOT" "$el" "$SECS" "$(sumgps)" "$(getk шары_получ)"; done
G=$(sumgps); RX=$(getk шары_получ); TX=$(getk шары_отосл); SPS=$(awk "BEGIN{printf \"%.2f\",${TX:-0}/$SECS}")
ND=$(getf шары_на_ноде); NA=$(getf accept); NS=$(getf stale); NR=$(getf reject)
echo "================= ИТОГ ($MODE, SLOT $SLOT) ================="
printf "  экземпляров: %s   инстансов: %s   %s   бинарь: %s   время: %sс\n" "$EXE" "$INST" "$HW" "$BIN" "$SECS"
printf "  СКОРОСТЬ:  %s g/s\n" "${G:-нет данных}"
printf "  прокси:    найдено=%s отослано=%s  (%s шар/сек)\n" "${RX:-0}" "${TX:-0}" "$SPS"
printf "  НА НОДЕ:   долетело=%s  accept=%s stale=%s reject=%s\n" "${ND:-0}" "${NA:-0}" "${NS:-0}" "${NR:-0}"
echo "==========================================================="
slotstop
