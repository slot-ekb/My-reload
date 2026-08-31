#!/bin/bash
# Тест группировки: N солверов-инстансов на процесс, процессов = ядра/N.
# Одно соединение на процесс => меньше коннектов к ноде.
# Использование: ./grouptest.sh [N инстансов] [секунды] [fake|node]
# Чистит ТОЛЬКО свои gt* (production ecpu* НЕ трогает).
cd "$(dirname "$0")"; BASE="$(pwd)"; . ./config.env
N=${1:-4}; SECS=${2:-40}; TGT=${3:-fake}
export LD_LIBRARY_PATH="$BASE/lib"
CORES=$(nproc); PROCS=$(( CORES / N )); [ "$PROCS" -lt 1 ] && PROCS=1
[ "$TGT" = "node" ] && STR="$STRATUM" || STR="127.0.0.1:3499"

if [ "$TGT" = "fake" ]; then pkill -f fakestratum.py 2>/dev/null; sleep 1; python3 fakestratum.py >/tmp/fake.log 2>&1 & sleep 2; fi

# N plugin-блоков (N независимых солверов в одном процессе = одно соединение)
BLK=""
for ((i=0;i<N;i++)); do BLK+='[[mining.miner_plugin_config]]\nplugin_name = "cuckatoo_mean_cpu_avx2_19"\n[mining.miner_plugin_config.parameters]\nnthreads = 1\n'; done

rm -rf ginst
for ((p=0;p<PROCS;p++)); do
  D="$BASE/ginst/p$p"; mkdir -p "$D"
  cat > "$D/epic-miner.toml" <<TOML
[logging]
log_to_stdout = false
log_to_file = true
file_log_level = "Info"
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
  screen -dmS "gt$p" bash -c "cd '$D'; export LD_LIBRARY_PATH='$BASE/lib'; while true; do '$BASE/epic-miner' -c epic-miner.toml; sleep 3; done"
done

echo ">>> N=$N инстансов/процесс | процессов=$PROCS (=столько соединений) | цель=$TGT | жду ${SECS}с..."
sleep "$SECS"
echo ">>> хешрейт:"
for f in "$BASE"/ginst/*/miner.log; do grep -oE "at [0-9.]+ gps" "$f" 2>/dev/null | awk '$2>0{v=$2} END{if(v!="")print v}'; done | awk '{s+=$1;n++} END{printf "cuckoo: %.0f gps | процессов %d | средн %.1f\n",s,n,(n?s/n:0)}'
echo ">>> соединений к стратуму: $(ss -tn 2>/dev/null | grep -cE ':3499|:3416')"
# cleanup ТОЛЬКО gt* (не трогаем ecpu*/production)
for s in $(screen -ls 2>/dev/null | grep -oE '[0-9]+\.gt[0-9]+'); do screen -S "$s" -X quit; done
[ "$TGT" = "fake" ] && pkill -f fakestratum.py 2>/dev/null
rm -rf "$BASE"/ginst
echo ">>> тест завершён (production ecpu* не тронут)"
