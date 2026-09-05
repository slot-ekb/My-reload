#!/bin/bash
# CPU-воркеры. Все крутилки в config.env (как аргументы mtest):
#   WORKERS   = число ПРОЦЕССОВ майнера (0 = авто: заполнить ядра)
#   INSTANCES = солверов в одном процессе (томл)
#   NTHREADS  = потоков на один солвер
#   -> каждому процессу выделяется INSTANCES*NTHREADS нитей, пиновка taskset.
#   USE_PROXY=on -> на прокси(127.0.0.1:PROXY_PORT); off -> прямо на NODE.
BASE="$(cd "$(dirname "$0")"&&pwd)"; . "$BASE/config.env"
[ "${PERF:-off}" = on ] && echo performance | tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor >/dev/null 2>&1
NG=$(nvidia-smi -L 2>/dev/null | grep -c '^GPU'); [ "$NG" -lt 1 ] && NG=0
PPG=${PROC_PER_GPU:-2}; [ "$PPG" -lt 1 ] && PPG=1
G=$(( NG * PPG ))
. "$BASE/aff.sh" "$G" >/dev/null 2>&1 || true; IFS=',' read -ra POOL <<< "${CPUSET:-}"
[ "${#POOL[@]}" -lt 1 ] && POOL=($(seq 0 $(($(nproc)-1))))
L=${#POOL[@]}
RESERVE=${RESERVE:-2}
INS=${INSTANCES:-1}; [ "$INS" -lt 1 ] && INS=1
NTH=${NTHREADS:-1}; [ "$NTH" -lt 1 ] && NTH=1
PERPROC=$(( INS * NTH ))                       # нитей на один процесс
USABLE=$(( L - RESERVE )); [ "$USABLE" -lt "$PERPROC" ] && USABLE=$PERPROC
if [ "${WORKERS:-0}" -gt 0 ]; then PROCS=$WORKERS; else PROCS=$(( USABLE / PERPROC )); fi
[ "$PROCS" -lt 1 ] && PROCS=1
MAXP=$(( L / PERPROC )); [ "$MAXP" -lt 1 ] && MAXP=1
[ "$PROCS" -gt "$MAXP" ] && PROCS=$MAXP
# куда слать
if [ "${USE_PROXY:-off}" = on ]; then STR="127.0.0.1:${PROXY_PORT:-3400}"; else STR="$NODE"; fi
export EPIC_RANGE=${RANGE:-1}; MB="$BASE/bin/epic-miner-${MINER:-orig}"
BLK=""; for ((k=0;k<INS;k++)); do BLK+='[[mining.miner_plugin_config]]\nplugin_name = "cuckatoo_mean_cpu_avx2_19"\n[mining.miner_plugin_config.parameters]\nnthreads = '"$NTH"'\n'; done
for ((p=0;p<PROCS;p++)); do
  D="$BASE/inst/w$p"; mkdir -p "$D"
  LT=false; [ "$LOGS" = on ] && [ "$p" = 0 ] && LT=true
  cat > "$D/epic-miner.toml" <<TOML
[logging]
log_to_stdout = false
log_to_file = $LT
file_log_level = "Info"
stdout_log_level = "Info"
log_file_path = "$D/miner.log"
log_file_append = false
[mining]
algorithm = "Cuckoo"
run_tui = false
stratum_server_addr = "$STR"
stratum_server_tls_enabled = false
miner_plugin_dir = "$BASE/plugins"
[mining.randomx_config]
threads = 1
jit = true
large_pages = false
hard_aes = true
[[mining.gpu_config]]
device = 0
driver = 2
TOML
  printf "$BLK" >> "$D/epic-miner.toml"
  sl=""; for ((q=0;q<PERPROC;q++)); do ci=$(( p*PERPROC + q )); [ -n "${POOL[$ci]}" ] && sl+="${POOL[$ci]},"; done; sl=${sl%,}
  PIN=""; [ -n "$sl" ] && PIN="taskset -c $sl "
  screen -S "wk$p" -X quit 2>/dev/null
  screen -dmS "wk$p" bash -c "cd '$D'; export LD_LIBRARY_PATH='$BASE/lib'; export EPIC_RANGE=${RANGE:-1}; while true; do ${PIN}'$MB' -c epic-miner.toml; sleep 3; done"
done
echo "CPU: $PROCS проц × $INS инст × $NTH пот = $((PROCS*PERPROC)) нитей (пул $L, GPU занял $G, режим=$([ "${USE_PROXY:-off}" = on ] && echo прокси || echo прямо)) -> $STR"
