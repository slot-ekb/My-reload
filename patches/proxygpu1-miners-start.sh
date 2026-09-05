#!/bin/bash
# GPU-майнеры НАПРЯМУЮ на ноду (без прокси), настраиваемо:
#   PROC_PER_GPU   = процессов на карту
#   CORES_PER_GPU  = физ.ядер на карту (по умолч. = PROC_PER_GPU, т.е. 1 ядро/процесс).
#     Процессы карты раскидываются round-robin по её ядрам:
#     PROC=CORES -> 1 процесс на ядро; PROC>CORES -> делят ядро; PROC<CORES -> ядра в запас.
#   USE_PROXY=on -> через прокси(:PROXY_PORT); off -> прямо на NODE.
BASE="$(cd "$(dirname "$0")"&&pwd)"; . "$BASE/config.env"
[ "${PERF:-off}" = on ] && echo performance | tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor >/dev/null 2>&1
NG=$(nvidia-smi -L 2>/dev/null | grep -c '^GPU'); [ "$NG" -lt 1 ] && NG=1
PPG=${PROC_PER_GPU:-2}; [ "$PPG" -lt 1 ] && PPG=1
CPG=${CORES_PER_GPU:-$PPG}; [ "$CPG" -lt 1 ] && CPG=1
G=$(( NG * CPG ))                              # всего физ.ядер под карты
. "$BASE/aff.sh" "$G" >/dev/null 2>&1 || true; IFS=',' read -ra GA <<< "${GPUSET:-}"
declare -A _s; CORES=()
for c in "${GA[@]}"; do
  k="$(cat /sys/devices/system/cpu/cpu$c/topology/physical_package_id 2>/dev/null):$(cat /sys/devices/system/cpu/cpu$c/topology/core_id 2>/dev/null)"
  [ -n "${_s[$k]:-}" ] && continue; _s[$k]=1; CORES+=("$c")
done
[ "${#CORES[@]}" -lt 1 ] && for ((c=0;c<G;c++)); do CORES+=("$c"); done
if [ "${USE_PROXY:-off}" = on ]; then STR="127.0.0.1:${PROXY_PORT:-3401}"; else STR="$NODE"; fi
export EPIC_RANGE=${RANGE:-1}; MB="$BASE/bin/epic-miner-${MINER:-orig}"
idx=0
for ((card=0;card<NG;card++)); do
  for ((j=0;j<PPG;j++)); do
    D="$BASE/instances/ecuk$idx"; mkdir -p "$D"
    LT=false; [ "$LOGS" = on ] && [ "$idx" = 0 ] && LT=true
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
device = $card
driver = 2
[[mining.miner_plugin_config]]
plugin_name = "cuckatoo_lean_cuda_19"
[mining.miner_plugin_config.parameters]
device = $card
TOML
    ci=$(( card*CPG + (j % CPG) )); core="${CORES[$ci]}"
    PIN=""; [ -n "$core" ] && PIN="taskset -c $core "
    screen -S "ecuk$idx" -X quit 2>/dev/null
    screen -dmS "ecuk$idx" bash -c "cd '$D'; export LD_LIBRARY_PATH='$BASE/lib'; export EPIC_RANGE=${RANGE:-1}; while true; do ${PIN}'$MB' -c epic-miner.toml; sleep 3; done"
    idx=$(( idx + 1 ))
  done
done
echo "GPU: карт=$NG × $PPG проц = $idx процессов на $((NG*CPG)) ядрах ($CPG ядер/карту) -> $STR | бинарь=${MINER}"
