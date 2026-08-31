#!/bin/bash
# Тест шар через ОДИН прокси на фейк-ноду. Считает submit'ы счётчиком прокси.
# ./sharetest.sh [N инстансов на процесс] [секунды]
# Чистит только своё (sttest.toml / порты 3499,3401), production не трогает.
cd "$(dirname "$0")"; BASE="$(pwd)"
N=${1:-4}; SECS=${2:-10}
CORES=$(nproc); PROCS=$(( CORES / N )); [ "$PROCS" -lt 1 ] && PROCS=1

pkill -f fakestratum.py 2>/dev/null
pkill -f "epic_proxy.py 127.0.0.1:3499" 2>/dev/null
pkill -f "epic-miner -c sttest.toml" 2>/dev/null
sleep 1
python3 fakestratum.py >/tmp/fake.log 2>&1 &
sleep 2
python3 -u epic_proxy.py 127.0.0.1:3499 3401 >/tmp/proxy_test.log 2>&1 &
sleep 2

BLK=""
for ((i=0;i<N;i++)); do BLK+='[[mining.miner_plugin_config]]\nplugin_name = "cuckatoo_mean_cpu_avx2_19"\n[mining.miner_plugin_config.parameters]\nnthreads = 1\n'; done
rm -rf stinst
for ((p=0;p<PROCS;p++)); do
  D="$BASE/stinst/p$p"; mkdir -p "$D"
  cat > "$D/sttest.toml" <<TOML
[logging]
log_to_stdout = false
log_to_file = true
file_log_level = "Info"
stdout_log_level = "Info"
log_file_path = "$D/m.log"
log_file_append = false
[mining]
algorithm = "Cuckoo"
run_tui = false
stratum_server_addr = "127.0.0.1:3401"
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
  printf "$BLK" >> "$D/sttest.toml"
  ( cd "$D" && LD_LIBRARY_PATH="$BASE/lib" "$BASE/epic-miner" -c sttest.toml >/dev/null 2>&1 ) &
done

echo ">>> N=$N инст/процесс | процессов=$PROCS (=коннектов к прокси) | 1 прокси -> фейк | ${SECS}с..."
sleep "$SECS"
SUB=$(grep -oE 'submits=[0-9]+' /tmp/proxy_test.log | tail -1 | grep -oE '[0-9]+')
GPS=$(for f in stinst/*/m.log; do grep -oE 'at [0-9.]+ gps' "$f" 2>/dev/null | awk '$2>0{v=$2} END{if(v!="")print v}'; done | awk '{s+=$1} END{printf "%.0f",s}')
CONN=$(ss -Htn state established '( dport = :3401 )' 2>/dev/null | wc -l)
echo ">>> submit'ов через прокси : ${SUB:-0}  (= $(awk "BEGIN{printf \"%.1f\", ${SUB:-0}/$SECS}")/сек)"
echo ">>> g/s суммарно           : ${GPS:-0}"
echo ">>> коннектов к прокси      : $CONN (процессов $PROCS)"

pkill -f "epic-miner -c sttest.toml" 2>/dev/null
pkill -f "epic_proxy.py 127.0.0.1:3499" 2>/dev/null
pkill -f fakestratum.py 2>/dev/null
rm -rf stinst
echo ">>> DONE (production не тронут)"
