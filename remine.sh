#!/bin/bash
# Перезапуск ТОЛЬКО майнеров по свежему config.env. ПРОКСИ не трогаем.
cd "$(dirname "$0")"; BASE="$(pwd)"; . ./config.env
export LD_LIBRARY_PATH="$BASE/lib:$LD_LIBRARY_PATH"
mkdir -p inst

# погасить только майнеры (pcu*), прокси (proxycu-px) оставить как есть
for s in $(screen -ls 2>/dev/null | grep -oE 'pcu[0-9]+'); do screen -S "$s" -X quit; done
pkill -f "$BASE/bin/epic-miner" 2>/dev/null
sleep 1

# пересоздать майнеров по env (WORKERS/INSTANCES)
N=${WORKERS:-0}; [ "$N" -le 0 ] && N=$(nproc)
INS=${INSTANCES:-1}; [ "$INS" -lt 1 ] && INS=1
PROCS=$(( N / INS )); [ "$PROCS" -lt 1 ] && PROCS=1
BLK=""
for ((i=0;i<INS;i++)); do BLK+='[[mining.miner_plugin_config]]\nplugin_name = "cuckatoo_mean_cpu_avx2_19"\n[mining.miner_plugin_config.parameters]\nnthreads = 1\n'; done

for ((p=0;p<PROCS;p++)); do
  D="$BASE/inst/w$p"; mkdir -p "$D"
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
stratum_server_addr = "127.0.0.1:$PROXY_PORT"
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
TOML
  printf "$BLK" >> "$D/epic-miner.toml"
  screen -S "pcu$p" -X quit 2>/dev/null
  screen -dmS "pcu$p" bash -c "cd '$D'; export LD_LIBRARY_PATH='$BASE/lib'; while true; do '$BASE/bin/epic-miner' -c epic-miner.toml; sleep 3; done"
done
# статус прокси — только показать, не трогать
if pgrep -f "$BASE/bin/epic_proxy.py" >/dev/null; then PX="работает"; else PX="*** СТОП ***"; fi
echo "майнеры перезапущены: $PROCS процессов × $INS инст = $((PROCS*INS)) солверов -> :$PROXY_PORT"
echo "прокси: $PX (не тронут)"
