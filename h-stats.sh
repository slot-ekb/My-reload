#!/usr/bin/env bash
# h-stats.sh -- report miner stats to the HiveOS agent.
#
# v3: reads matador's own combined stdout log instead of polling the /summary
# HTTP API. matador already logs real, working numbers there every cycle:
#   [stratum] worker.report_metrics sent: nps=399 shares=0
#   [stats-all] gpus=6/6 ep/s=2 acc=0 rej=0 pow=1218W maxtemp=79C | per-gpu ep/s: 0 0 0 0 0 0
# (see project_cobra_hstats_fix memory for the history of why /summary-based
# approaches kept reading 0: its own .averages."1h"/"24h".episode_per_s field
# never populates even under real load -- a matador-side bug in that specific
# field, unrelated to these log lines, which are correct and live).
#
# "nps" here is matador's own pool-facing throughput figure (confirmed to
# match /summary's solver_nps exactly, ~380-400 on this rig) -- this is what
# gets shown as the rig's hashrate. It runs well above [stats-all]'s ep/s
# (completed full ENC_RC episodes/s, ~1-2 aggregate for 6 cards -- see
# BUILDING.md's ~1.2/s-per-card note): nps counts finer-grained solver
# throughput, ep/s counts only fully finished episodes. nps is what matador
# itself reports to pools as its headline number, so it's what we show too.
#
# No real per-card breakdown exists in either log line (per-gpu ep/s in
# [stats-all] rounds every fractional card down to 0, same reason as nps
# would if split honestly) -- hs[] below is the aggregate nps divided evenly
# across detected cards, an approximation flagged here rather than silently
# presented as a precise per-card measurement.

[[ -e /hive/custom ]] && . /hive/custom/cobra/h-manifest.conf
[[ -e /hive/miners/custom ]] && . /hive/miners/custom/cobra/h-manifest.conf
[[ -n "${MATADOR_HIVE_DIR:-}" && -e "$MATADOR_HIVE_DIR/h-manifest.conf" ]] && . "$MATADOR_HIVE_DIR/h-manifest.conf"

LOGFILE="${MATADOR_STATS_LOGFILE:-${CUSTOM_LOG_BASENAME:-/var/log/miner/custom/custom}.log}"
API_HOST="${MATADOR_API_HOST:-127.0.0.1}"
API_PORT="${CUSTOM_API_PORT:-4060}"

khs=0
stats='{"total_khs":0,"khs":0,"hs_units":"hs","hs":[0],"temp":[0],"fan":[0],"uptime":0,"ver":"unknown","ar":[0,0],"algo":"btx","bus_numbers":[0]}'

strip_ansi() { sed -E 's/\x1b\[[0-9;]*m//g'; }

if [[ -r "$LOGFILE" ]] && command -v jq >/dev/null 2>&1; then
    last_nps_line=$(strip_ansi < "$LOGFILE" | grep -a 'worker.report_metrics sent:' | tail -1)
    total_nps=$(grep -oE 'nps=[0-9.]+' <<< "$last_nps_line" | head -1 | cut -d= -f2)
    total_nps="${total_nps:-0}"

    last_stats_line=$(strip_ansi < "$LOGFILE" | grep -a '\[stats-all\]' | tail -1)
    acc=$(grep -oE 'acc=[0-9]+' <<< "$last_stats_line" | cut -d= -f2)
    rej=$(grep -oE 'rej=[0-9]+' <<< "$last_stats_line" | cut -d= -f2)
    acc="${acc:-0}"; rej="${rej:-0}"

    # uptime + version aren't in the log lines -- one cheap call to the first
    # port's /summary for those two fields only (not the whole aggregation
    # loop that used to unreliably fan out across all 6 ports).
    uptime=0; ver="unknown"
    if command -v curl >/dev/null 2>&1; then
        s=$(curl -s --connect-timeout 1 --max-time 2 "http://${API_HOST}:${API_PORT}/summary" 2>/dev/null)
        if jq -e . >/dev/null 2>&1 <<< "$s"; then
            uptime=$(jq -r '.uptime_sec // 0' <<< "$s")
            ver=$(jq -r '.version // "unknown"' <<< "$s")
        fi
    fi

    # temp/fan/bus_numbers: nvidia-smi directly, keyed by PCI bus (matador's
    # own APIs carry neither fan nor a stable bus mapping we can trust here).
    gpu_count=0
    temp_arr="[]"; fan_arr="[]"; bus_arr="[]"
    if command -v nvidia-smi >/dev/null 2>&1; then
        temp_arr=$(nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader,nounits | jq -R . | jq -sc 'map(tonumber? // 0)')
        fan_list=()
        bus_list=()
        while IFS=, read -r fan bus; do
            fan="${fan// /}"; bus="${bus// /}"
            [[ "$fan" == *"N/A"* || -z "$fan" ]] && fan=0
            fan_list+=("$fan")
            bus_hex=$(grep -oE '[0-9A-Fa-f]+:[0-9A-Fa-f]+\.[0-9]+$' <<< "$bus" | cut -d: -f1)
            bus_list+=("$((16#${bus_hex:-0}))")
        done < <(nvidia-smi --query-gpu=fan.speed,pci.bus_id --format=csv,noheader,nounits 2>/dev/null)
        fan_arr=$(printf '%s\n' "${fan_list[@]}" | jq -R . | jq -sc 'map(tonumber? // 0)')
        bus_arr=$(printf '%s\n' "${bus_list[@]}" | jq -R . | jq -sc 'map(tonumber? // 0)')
        gpu_count=$(jq 'length' <<< "$temp_arr")
    fi
    [[ "$gpu_count" -lt 1 ]] && gpu_count=1

    per_card=$(awk -v n="$total_nps" -v c="$gpu_count" 'BEGIN{printf "%.3f", n/c}')
    hs_arr=$(jq -nc --argjson n "$gpu_count" --argjson v "$per_card" '[range($n) | $v]')

    # "nps" is matador's own pool-facing number, but it isn't episodes/s
    # directly -- confirmed against [stats-all]'s own "ep/s=2" (that line
    # truncates to an integer): nps=266 / 100 = 2.66, matching exactly.
    # So nps runs in centi-episodes/s; dividing by 100 recovers the real
    # episodes/s figure with the decimal precision the log line's integer
    # truncation throws away. That's what gets reported here.
    stats=$(jq -c -n \
        --argjson hs "$hs_arr" --argjson temp "$temp_arr" --argjson fan "$fan_arr" \
        --argjson bus "$bus_arr" --argjson total "$total_nps" --argjson acc "$acc" --argjson rej "$rej" \
        --argjson uptime "$uptime" --arg ver "$ver" '
        def r3: (. * 1000 | round) / 1000;
        {
            total_khs: (($total / 100) | r3), khs: (($total / 100) | r3),
            hs_units: "khs", hs: [$hs[] | (. / 100) | r3],
            temp: $temp, fan: $fan, uptime: $uptime, ver: $ver,
            ar: [$acc, $rej], algo: "btx", bus_numbers: $bus
        }')
    khs=$(jq -r '.khs' <<< "$stats")
fi

echo "khs:   $khs"
echo "stats: $stats"
