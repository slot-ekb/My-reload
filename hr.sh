#!/bin/bash
D="$(cd "$(dirname "$0")" && pwd)"
for f in "$D"/inst/*/miner.log; do grep -oE "at [0-9.]+ gps" "$f" 2>/dev/null | awk '$2>0{v=$2} END{if(v!="")print v}'; done | awk '{s+=$1;n++} END{printf "cuckoo: %.0f gps | воркеров %d | средн %.1f\n",s,n,(n?s/n:0)}'
