#!/bin/bash
# diffscan — РАСПРЕДЕЛЕНИЕ ВЕСА найденных шар (какие тяжелее), а не их количество.
# Майнеры бьют по фейк-ноде напрямую; фейк-нода считает вес каждой шары из pow и ведёт
# гистограмму «сколько шар >= порога». Сравнивай раскладки — форма распределения не меняется.
#   ./diffscan.sh [секунд] [воркеров] [инстансов] [nthreads] [бинарь]
#   ./diffscan.sh 60 4 1 1        # 4 солвера, 60с
BASE="$(cd "$(dirname "$0")"&&pwd)"; cd "$BASE"; . "$BASE/config.env"
SECS=${1:-${SECS:-60}}
NP=${2:-${WORKERS:-4}};   [ "$NP" -lt 1 ] && NP=1
INST=${3:-${INSTANCES:-1}}; [ "$INST" -lt 1 ] && INST=1
NTH=${4:-${NTHREADS:-1}}; [ "$NTH" -lt 1 ] && NTH=1
BIN=${5:-${BIN:-orig}}
. "$BASE/corelist.sh"                       # CORES[], NCORE
MB="$BASE/bin/epic-miner-${BIN}"
FP=${FAKE_PORT:-3799}
RUN="$BASE/run"; FLOG="$BASE/fake.log"
PERPROC=$(( INST * NTH ))

killall_(){
  for s in $(screen -ls 2>/dev/null | grep -oE '[0-9]+\.ds_[0-9]+'); do screen -S "$s" -X quit 2>/dev/null; done
  pkill -9 -f "$BASE/fakestratum.py $FP" 2>/dev/null
  for pid in $(pgrep -x epic-miner-orig; pgrep -x epic-miner-range); do
    case "$(readlink /proc/$pid/cwd 2>/dev/null)" in "$RUN"/*) kill -9 "$pid" 2>/dev/null;; esac
  done
}
trap 'killall_; exit 0' INT TERM
killall_; sleep 1; rm -rf "$RUN"; mkdir -p "$RUN"

DIFF="${DIFF:-1}" LOGW="${LOGW:-off}" setsid python3 "$BASE/fakestratum.py" "$FP" >"$FLOG" 2>&1 & sleep 1
export LD_LIBRARY_PATH="$BASE/lib" EPIC_RANGE="${RANGE:-1}"
for ((p=0;p<NP;p++)); do
  D="$RUN/w$p"; mkdir -p "$D"
  { echo '[logging]'; echo 'log_to_stdout = false'; echo 'log_to_file = true'
    echo 'file_log_level = "Info"'; echo 'stdout_log_level = "Info"'
    echo "log_file_path = \"$D/miner.log\""; echo 'log_file_append = false'
    echo '[mining]'; echo 'algorithm = "Cuckoo"'; echo 'run_tui = false'
    echo "stratum_server_addr = \"127.0.0.1:$FP\""; echo 'stratum_server_tls_enabled = false'
    echo "miner_plugin_dir = \"$BASE/plugins\""
    echo '[mining.randomx_config]'; echo 'threads = 1'; echo 'jit = true'; echo 'large_pages = false'; echo 'hard_aes = true'
    echo '[[mining.gpu_config]]'; echo 'device = 0'; echo 'driver = 2'
    for ((k=0;k<INST;k++)); do echo '[[mining.miner_plugin_config]]'; echo 'plugin_name = "cuckatoo_mean_cpu_avx2_19"'
      echo '[mining.miner_plugin_config.parameters]'; echo "nthreads = $NTH"; done
  } > "$D/epic-miner.toml"
  sl=""; for ((q=0;q<PERPROC;q++)); do ci=$(( p*PERPROC + q )); [ -n "${CORES[$ci]}" ] && sl+="${CORES[$ci]},"; done; sl=${sl%,}
  TASK=""; [ -n "$sl" ] && TASK="taskset -c $sl "
  screen -dmS "ds_$p" bash -c "cd '$D'; export LD_LIBRARY_PATH='$BASE/lib'; export EPIC_RANGE='${RANGE:-1}'; while true; do ${TASK}'$MB' -c epic-miner.toml; sleep 3; done"
done

echo ">>> diffscan: воркеров=$NP × инст=$INST × пот=$NTH = $((NP*PERPROC)) физ.ядер | DIFF=$DIFF | замер ${SECS}с..."
el=0; step=5
while [ "$el" -lt "$SECS" ]; do s=$step; [ $((el+step)) -gt "$SECS" ] && s=$((SECS-el)); sleep "$s"; el=$((el+s))
  printf "  [%2s/%sс] %s\n" "$el" "$SECS" "$(grep 'ВЕС-ГИСТОГРАММА' "$FLOG" | tail -1)"; done
echo "================= ИТОГ (вес шар) ================="
grep 'ВЕС-ГИСТОГРАММА' "$FLOG" | tail -1
echo "=================================================="
echo "≥1 = всего шар. Дальше — сколько ТЯЖЕЛЕЕ порога (≈ всего/порог). макс = самая тяжёлая (кандидат в блок)."
echo "Смени раскладку и сравни: форма (доли) не меняется, растёт только общий счётчик."
killall_
