#!/bin/bash
# CPU-воркеры НАПРЯМУЮ на ноду (без прокси). Меньше процессов: INSTANCES солверов в томл,
# каждому процессу выделяется INSTANCES физ.ядер (пиновка на срез ядер). GPU-ядра исключены.
BASE="$(cd "$(dirname "$0")"&&pwd)"; . "$BASE/config.env"
[ "${PERF:-off}" = on ] && echo performance | tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor >/dev/null 2>&1
NG=$(nvidia-smi -L 2>/dev/null | wc -l); [ "$NG" -lt 1 ] && NG=0
PPG=${PROC_PER_GPU:-2}; [ "$PPG" -lt 1 ] && PPG=1
G=$(( NG * PPG ))
# aff.sh с тем же G, что у GPU -> CPUSET = ядра БЕЗ занятых картами. Дедуп до 1 CPU на физ.ядро.
. "$BASE/aff.sh" "$G" >/dev/null 2>&1 || true; IFS=',' read -ra RAW <<< "${CPUSET:-}"
[ "${#RAW[@]}" -lt 1 ] && RAW=($(seq 0 $(($(nproc)-1))))
declare -A _s; CA=()
for c in "${RAW[@]}"; do
  k="$(cat /sys/devices/system/cpu/cpu$c/topology/physical_package_id 2>/dev/null):$(cat /sys/devices/system/cpu/cpu$c/topology/core_id 2>/dev/null)"
  [ -n "${_s[$k]:-}" ] && continue; _s[$k]=1; CA+=("$c")
done
NAVAIL=${#CA[@]}
RESERVE=${RESERVE:-2}
INS=${INSTANCES:-2}; [ "$INS" -lt 1 ] && INS=1
if [ "${WORKERS:-0}" -le 0 ]; then USE=$(( NAVAIL - RESERVE )); [ "$USE" -lt 1 ] && USE=1; else USE=$WORKERS; fi
[ "$USE" -gt "$NAVAIL" ] && USE=$NAVAIL
PROCS=$(( USE / INS )); [ "$PROCS" -lt 1 ] && PROCS=1
export EPIC_RANGE=${RANGE:-1}; MB="$BASE/bin/epic-miner-${MINER:-orig}"
BLK=""; for ((k=0;k<INS;k++)); do BLK+='[[mining.miner_plugin_config]]\nplugin_name = "cuckatoo_mean_cpu_avx2_19"\n[mining.miner_plugin_config.parameters]\nnthreads = 1\n'; done
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
stratum_server_addr = "$NODE"
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
  sl=""; for ((q=0;q<INS;q++)); do ci=$(( p*INS + q )); [ -n "${CA[$ci]}" ] && sl+="${CA[$ci]},"; done; sl=${sl%,}
  PIN=""; [ -n "$sl" ] && PIN="taskset -c $sl "
  screen -S "wk$p" -X quit 2>/dev/null
  screen -dmS "wk$p" bash -c "cd '$D'; export LD_LIBRARY_PATH='$BASE/lib'; export EPIC_RANGE=${RANGE:-1}; while true; do ${PIN}'$MB' -c epic-miner.toml; sleep 3; done"
done
echo "CPU-воркеры: $PROCS проц × $INS инст = $((PROCS*INS)) солверов на $USE ядрах (GPU занял $G) -> нода $NODE | бинарь=${MINER}"
