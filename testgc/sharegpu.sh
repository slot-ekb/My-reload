#!/bin/bash
# GPU-тест шар на фейк-ноде: фейк -> прокси(:GPU_PROXY_PORT) -> майнер на карты.
# На каждую карту INST солверов (cuckatoo_lean_cuda_19).
# Все аргументы можно опустить (или поставить -) => берётся из config.env.
#
#   ./sharegpu.sh [секунд] [карт] [инстансов] [бинарь]
#      секунд     длительность замера          (по умолч. SECS)
#      карт       сколько карт; 0=все           (по умолч. GPU_CARDS)
#      инстансов  солверов на одну карту        (по умолч. GPU_INSTANCES)
#      бинарь     orig | range                  (по умолч. BIN)
BASE="$(cd "$(dirname "$0")"&&pwd)"; . "$BASE/config.env"
val(){ [ -z "$1" ] || [ "$1" = "-" ] && echo "$2" || echo "$1"; }
SECS=$(val "$1" "${SECS:-60}")
CARDS=$(val "$2" "${GPU_CARDS:-0}")
INST=$(val "$3" "${GPU_INSTANCES:-1}")
BIN=$(val "$4" "${BIN:-orig}")
export LD_LIBRARY_PATH="$BASE/lib"; export EPIC_RANGE="${RANGE:-1}"
MB="$BASE/bin/epic-miner-${BIN}"
"$BASE/stop.sh" >/dev/null 2>&1; sleep 1

NG=$(nvidia-smi -L 2>/dev/null | wc -l); [ "$NG" -lt 1 ] && NG=1
N=${CARDS:-0}; [ "$N" -le 0 ] && N=$NG
[ "$N" -gt "$NG" ] && N=$NG
[ "$INST" -lt 1 ] && INST=1

setsid python3 "$BASE/fakestratum.py" "$FAKE_PORT" >"$BASE/fake.log" 2>&1 & sleep 1
setsid python3 -u "$BASE/bin/epic_proxy.py" "127.0.0.1:$FAKE_PORT" "$GPU_PROXY_PORT" >"$BASE/proxy_gpu.log" 2>&1 & sleep 2

echo ">>> GPU: карт=$N инстансов_на_карту=$INST бинарь=$BIN замер ${SECS}с..."
for ((i=0;i<N;i++)); do
  D="$BASE/run/gpu/g$i"; mkdir -p "$D"
  { cat <<TOML
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
stratum_server_addr = "127.0.0.1:$GPU_PROXY_PORT"
stratum_server_tls_enabled = false
miner_plugin_dir = "$BASE/plugins"
[mining.randomx_config]
threads = 1
jit = true
large_pages = false
hard_aes = true
[[mining.gpu_config]]
device = $i
driver = 2
TOML
  for ((k=0;k<INST;k++)); do printf '[[mining.miner_plugin_config]]\nplugin_name = "cuckatoo_lean_cuda_19"\n[mining.miner_plugin_config.parameters]\ndevice = %d\n' "$i"; done
  } > "$D/epic-miner.toml"
  screen -dmS "tg$i" bash -c "cd '$D'; export LD_LIBRARY_PATH='$BASE/lib'; export EPIC_RANGE='${RANGE:-1}'; while true; do '$MB' -c epic-miner.toml; sleep 3; done"
done

# суммарная скорость по логам карт (последнее gps каждой) + per-card
sum_gps(){ local s=0 v f; for f in "$BASE"/run/gpu/*/miner.log; do [ -f "$f" ] || continue; v=$(grep -oE 'at [0-9.]+ gps' "$f" 2>/dev/null | tail -1 | grep -oE '[0-9.]+'); [ -n "$v" ] && s=$(awk "BEGIN{printf \"%.2f\",$s+$v}"); done; echo "$s"; }
getk(){ grep 'СТАТ' "$BASE/proxy_gpu.log" | tail -1 | grep -oE "$1=[0-9]+" | grep -oE '[0-9]+$'; }

el=0; step=5
while [ "$el" -lt "$SECS" ]; do
  sl=$step; [ $((el+step)) -gt "$SECS" ] && sl=$((SECS-el)); sleep "$sl"; el=$((el+sl))
  printf "  [%2s/%sс] g/s=%-8s шары=%-5s задания=%-4s\n" "$el" "$SECS" "$(sum_gps)" "$(getk шары_получ)" "$(getk задания_получ)"
done

G=$(sum_gps); RX=$(getk шары_получ); TX=$(getk шары_отосл); JR=$(getk задания_получ); JT=$(getk задания_розд)
SPS=$(awk "BEGIN{printf \"%.2f\", ${TX:-0}/$SECS}")
echo "======================= ИТОГ GPU ======================="
printf "  время:        %sс\n" "$SECS"
printf "  карт:         %s   инстансов/карту: %s   бинарь: %s\n" "$N" "$INST" "$BIN"
echo   "  скорость по картам:"
for ((i=0;i<N;i++)); do v=$(grep -oE 'at [0-9.]+ gps' "$BASE/run/gpu/g$i/miner.log" 2>/dev/null | tail -1 | grep -oE '[0-9.]+'); printf "     карта %s: %s g/s\n" "$i" "${v:-нет данных}"; done
printf "  СКОРОСТЬ:     %s g/s  (сумма по картам)\n" "$G"
printf "  шары:         найдено=%s  отослано=%s   (%s шар/сек)\n" "${RX:-0}" "${TX:-0}" "$SPS"
printf "  задания:      получено=%s  роздано=%s\n" "${JR:-0}" "${JT:-0}"
echo "========================================================"
"$BASE/stop.sh" >/dev/null 2>&1
