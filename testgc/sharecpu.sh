#!/bin/bash
# CPU-тест шар на фейк-ноде: фейк -> прокси(:CPU_PROXY_PORT) -> воркеры.
# Каждый воркер пиновится на своё физ.ядро; в воркере INST солверов, по NTH потоков.
# Все аргументы можно опустить (или поставить -) => берётся из config.env.
#
#   ./sharecpu.sh [секунд] [ядер] [инстансов] [nthreads] [бинарь]
#      секунд     длительность замера            (по умолч. SECS)
#      ядер       сколько физ.ядер/воркеров; 0=авто (физ.ядра-CPU_RESERVE)
#      инстансов  солверов в одном воркере        (по умолч. CPU_INSTANCES)
#      nthreads   потоков на солвер               (по умолч. CPU_NTHREADS)
#      бинарь     orig | range                    (по умолч. BIN)
BASE="$(cd "$(dirname "$0")"&&pwd)"; . "$BASE/config.env"
val(){ [ -z "$1" ] || [ "$1" = "-" ] && echo "$2" || echo "$1"; }
SECS=$(val "$1" "${SECS:-60}")
CORESN=$(val "$2" "${CPU_WORKERS:-0}")
INST=$(val "$3" "${CPU_INSTANCES:-1}")
NTH=$(val "$4" "${CPU_NTHREADS:-1}")
BIN=$(val "$5" "${BIN:-orig}")
export LD_LIBRARY_PATH="$BASE/lib"; export EPIC_RANGE="${RANGE:-1}"
MB="$BASE/bin/epic-miner-${BIN}"
"$BASE/stop.sh" >/dev/null 2>&1; sleep 1

setsid python3 "$BASE/fakestratum.py" "$FAKE_PORT" >"$BASE/fake.log" 2>&1 & sleep 1
setsid python3 -u "$BASE/bin/epic_proxy.py" "127.0.0.1:$FAKE_PORT" "$CPU_PROXY_PORT" >"$BASE/proxy_cpu.log" 2>&1 & sleep 2

# по одному логич.CPU на физ.ядро
mapfile -t ALL < <(seq 0 $(($(nproc)-1)))
declare -A seen; CORES=()
for c in "${ALL[@]}"; do
  k="$(cat /sys/devices/system/cpu/cpu$c/topology/physical_package_id 2>/dev/null):$(cat /sys/devices/system/cpu/cpu$c/topology/core_id 2>/dev/null)"
  [ -n "${seen[$k]:-}" ] && continue; seen[$k]=1; CORES+=("$c")
done
NAVAIL=${#CORES[@]}
if [ "${CORESN:-0}" -le 0 ]; then N=$(( NAVAIL - ${CPU_RESERVE:-2} )); [ "$N" -lt 1 ] && N=1; else N=$CORESN; fi
[ "$N" -gt "$NAVAIL" ] && N=$NAVAIL
[ "$INST" -lt 1 ] && INST=1

BLK=""; for ((k=0;k<INST;k++)); do BLK+='[[mining.miner_plugin_config]]\nplugin_name = "cuckatoo_mean_cpu_avx2_19"\n[mining.miner_plugin_config.parameters]\nnthreads = '"$NTH"'\n'; done
echo ">>> CPU: ядер/воркеров=$N (из $NAVAIL) инстансов_на_воркер=$INST nthreads=$NTH бинарь=$BIN замер ${SECS}с..."
for ((p=0;p<N;p++)); do
  D="$BASE/run/cpu/w$p"; mkdir -p "$D"
  cat > "$D/epic-miner.toml" <<TOML
[logging]
log_to_stdout = false
log_to_file = true
file_log_level = "Info"
stdout_log_level = "Info"
log_file_path = "$D/miner.log"
log_file_append = false
[mining]
algorithm = "Cuckoo"
run_tui = false
stratum_server_addr = "127.0.0.1:$CPU_PROXY_PORT"
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
  screen -dmS "tw$p" bash -c "cd '$D'; export LD_LIBRARY_PATH='$BASE/lib'; export EPIC_RANGE='${RANGE:-1}'; while true; do taskset -c ${CORES[$p]} '$MB' -c epic-miner.toml; sleep 3; done"
done

# суммарная скорость по логам воркеров (последнее gps каждого)
sum_gps(){ local s=0 v f; for f in "$BASE"/run/cpu/*/miner.log; do [ -f "$f" ] || continue; v=$(grep -oE 'at [0-9.]+ gps' "$f" 2>/dev/null | tail -1 | grep -oE '[0-9.]+'); [ -n "$v" ] && s=$(awk "BEGIN{printf \"%.2f\",$s+$v}"); done; echo "$s"; }
getk(){ grep 'СТАТ' "$BASE/proxy_cpu.log" | tail -1 | grep -oE "$1=[0-9]+" | grep -oE '[0-9]+$'; }

# live-вывод раз в 5с
el=0; step=5
while [ "$el" -lt "$SECS" ]; do
  sl=$step; [ $((el+step)) -gt "$SECS" ] && sl=$((SECS-el)); sleep "$sl"; el=$((el+sl))
  printf "  [%2s/%sс] g/s=%-8s шары=%-5s задания=%-4s\n" "$el" "$SECS" "$(sum_gps)" "$(getk шары_получ)" "$(getk задания_получ)"
done

G=$(sum_gps); RX=$(getk шары_получ); TX=$(getk шары_отосл); JR=$(getk задания_получ); JT=$(getk задания_розд)
SPS=$(awk "BEGIN{printf \"%.2f\", ${TX:-0}/$SECS}")
echo "======================= ИТОГ CPU ======================="
printf "  время:        %sс\n" "$SECS"
printf "  воркеров:     %s   инстансов/воркер: %s   nthreads: %s   бинарь: %s\n" "$N" "$INST" "$NTH" "$BIN"
printf "  СКОРОСТЬ:     %s g/s  (сумма по воркерам)\n" "$G"
printf "  шары:         найдено=%s  отослано=%s   (%s шар/сек)\n" "${RX:-0}" "${TX:-0}" "$SPS"
printf "  задания:      получено=%s  роздано=%s\n" "${JR:-0}" "${JT:-0}"
echo "========================================================"
"$BASE/stop.sh" >/dev/null 2>&1
