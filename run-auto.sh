#!/bin/bash
# Самонастраивающийся launcher: сам определяет NUMA-узлы и ядра,
# привязывает воркер к ядру (+ к локальной памяти, если есть numactl и >1 узла),
# включает huge pages. Ничего вручную настраивать не надо на разных машинах.
cd "$(dirname "$0")"; BASE="$(pwd)"; . ./config.env
export LD_LIBRARY_PATH="$BASE/lib:$LD_LIBRARY_PATH"
NTH=${NTHREADS:-1}

# --- huge pages (best-effort, для memory-bound mean-солвера) ---
if [ "${HUGEPAGES:-1}" = "1" ]; then
  echo always > /sys/kernel/mm/transparent_hugepage/enabled 2>/dev/null || true
  echo 2048 > /proc/sys/vm/nr_hugepages 2>/dev/null || true
fi

HAVE_NUMACTL=0; command -v numactl >/dev/null 2>&1 && HAVE_NUMACTL=1

# --- собрать пары (numa_node : cpu) из /sys, без зависимостей ---
PAIRS=()
for nd in /sys/devices/system/node/node[0-9]*; do
  [ -d "$nd" ] || continue
  n=$(basename "$nd" | sed 's/node//')
  list=$(cat "$nd/cpulist" 2>/dev/null); [ -z "$list" ] && continue
  IFS=',' read -ra parts <<< "$list"
  for p in "${parts[@]}"; do
    if [[ "$p" == *-* ]]; then a=${p%-*}; b=${p#*-}; for ((c=a;c<=b;c++)); do PAIRS+=("$n:$c"); done
    else PAIRS+=("$n:$p"); fi
  done
done
# fallback: нет NUMA-инфы -> все ядра как узел 0
if [ ${#PAIRS[@]} -eq 0 ]; then
  for ((c=0;c<$(nproc);c++)); do PAIRS+=("0:$c"); done
fi

NODES=$(printf '%s\n' "${PAIRS[@]}" | cut -d: -f1 | sort -u | wc -l)
echo "Авто: воркеров=${#PAIRS[@]}  NUMA-узлов=$NODES  numactl=$HAVE_NUMACTL  nthreads=$NTH  стратум=$STRATUM"

w=0
for pair in "${PAIRS[@]}"; do
  node=${pair%:*}; cpu=${pair#*:}
  INST="$BASE/inst/w$w"; mkdir -p "$INST"
  cat > "$INST/epic-miner.toml" <<TOML
[logging]
log_to_stdout = false
log_to_file = true
file_log_level = "Info"
stdout_log_level = "Info"
log_file_path = "$INST/miner.log"
log_file_append = false
[mining]
algorithm = "Cuckoo"
run_tui = false
stratum_server_addr = "$STRATUM"
stratum_server_tls_enabled = false
$( [ -n "$LOGIN" ] && echo "stratum_server_login = \"$LOGIN\"" )
miner_plugin_dir = "$BASE/plugins"
[mining.randomx_config]
threads = 1
jit = true
large_pages = false
hard_aes = true
[[mining.gpu_config]]
device = 0
driver = 2
[[mining.miner_plugin_config]]
plugin_name = "cuckatoo_mean_cpu_avx2_19"
[mining.miner_plugin_config.parameters]
nthreads = $NTH
TOML
  screen -S "ecpu$w" -X quit >/dev/null 2>&1
  if [ "$HAVE_NUMACTL" = "1" ] && [ "$NODES" -gt 1 ] && [ "${NUMA:-1}" = "1" ]; then
    BIND="numactl --membind=$node --physcpubind=$cpu"
  else
    BIND="taskset -c $cpu"
  fi
  screen -dmS "ecpu$w" bash -c "cd '$INST'; export LD_LIBRARY_PATH='$BASE/lib'; while true; do $BIND '$BASE/epic-miner' -c epic-miner.toml; sleep ${RESTART_DELAY:-3}; done"
  w=$((w+1))
done
echo "запущено $w воркеров (привязка: $([ "$HAVE_NUMACTL" = 1 ] && [ "$NODES" -gt 1 ] && echo NUMA+ядро || echo ядро))"
