#!/bin/bash
# CPU-воркеры НАПРЯМУЮ на ноду (без прокси).
# WORKERS = ЧИСЛО ПРОЦЕССОВ (0 = авто: по физ.ядрам, 1 солвер на ядро).
# INSTANCES = солверов в одном процессе; процессу выделяется столько же нитей.
# Пул нитей = все логические CPU (с HT) минус ядра, занятые картами. Можно ставить
# больше процессов, чем физ.ядер — пойдут на HT-нити.
BASE="$(cd "$(dirname "$0")"&&pwd)"; . "$BASE/config.env"
[ "${PERF:-off}" = on ] && echo performance | tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor >/dev/null 2>&1
NG=$(nvidia-smi -L 2>/dev/null | grep -c '^GPU'); [ "$NG" -lt 1 ] && NG=0
PPG=${PROC_PER_GPU:-2}; [ "$PPG" -lt 1 ] && PPG=1
G=$(( NG * PPG ))
# aff.sh: последние G физ.ядер -> GPU. CPUSET = ВСЕ логические нити (с HT) без GPU-ядер.
. "$BASE/aff.sh" "$G" >/dev/null 2>&1 || true; IFS=',' read -ra POOL <<< "${CPUSET:-}"
[ "${#POOL[@]}" -lt 1 ] && POOL=($(seq 0 $(($(nproc)-1))))
# число ФИЗ.ядер в пуле (дедуп) — для авто-режима
declare -A _s; PHYSN=0
for c in "${POOL[@]}"; do
  k="$(cat /sys/devices/system/cpu/cpu$c/topology/physical_package_id 2>/dev/null):$(cat /sys/devices/system/cpu/cpu$c/topology/core_id 2>/dev/null)"
  [ -n "${_s[$k]:-}" ] && continue; _s[$k]=1; PHYSN=$((PHYSN+1))
done
L=${#POOL[@]}
RESERVE=${RESERVE:-2}
INS=${INSTANCES:-2}; [ "$INS" -lt 1 ] && INS=1
if [ "${WORKERS:-0}" -gt 0 ]; then PROCS=$WORKERS
else PROCS=$(( (PHYSN - RESERVE) / INS )); [ "$PROCS" -lt 1 ] && PROCS=1; fi
MAXP=$(( L / INS )); [ "$MAXP" -lt 1 ] && MAXP=1
[ "$PROCS" -gt "$MAXP" ] && PROCS=$MAXP     # не больше, чем влезает нитей в пул
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
  sl=""; for ((q=0;q<INS;q++)); do ci=$(( p*INS + q )); [ -n "${POOL[$ci]}" ] && sl+="${POOL[$ci]},"; done; sl=${sl%,}
  PIN=""; [ -n "$sl" ] && PIN="taskset -c $sl "
  screen -S "wk$p" -X quit 2>/dev/null
  screen -dmS "wk$p" bash -c "cd '$D'; export LD_LIBRARY_PATH='$BASE/lib'; export EPIC_RANGE=${RANGE:-1}; while true; do ${PIN}'$MB' -c epic-miner.toml; sleep 3; done"
done
echo "CPU-воркеры: $PROCS проц × $INS инст = $((PROCS*INS)) солверов | физ.ядер в пуле=$PHYSN нитей=$L GPU занял=$G -> нода $NODE | бинарь=${MINER}"
