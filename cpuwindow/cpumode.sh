#!/bin/bash
# cpumode.sh — режимы частоты CPU БЕЗ установки. msr-бинарники лежат в пакете (bin/).
#   ./cpumode.sh max     — держать ядра ВСЕГДА на максимуме (для короткого cuckoo-окна)
#   ./cpumode.sh normal  — вернуть штатный ДИНАМИЧЕСКИЙ режим (как было до max)
#   ./cpumode.sh status  — показать текущее состояние
BASE="$(cd "$(dirname "$0")"&&pwd)"
MODE="${1:-status}"
PS=/sys/devices/system/cpu/intel_pstate
RD="$(command -v rdmsr || echo "$BASE/bin/rdmsr")"
WR="$(command -v wrmsr || echo "$BASE/bin/wrmsr")"
msr_ok(){ [ -x "$RD" ] && [ -x "$WR" ] && modprobe msr 2>/dev/null; [ -e /dev/cpu/0/msr ]; }

freqs(){ grep MHz /proc/cpuinfo | awk '{printf "%.0f\n",$4}' | sort -n | awk 'NR==1{min=$1}{max=$1}END{print "  частоты MHz: min="min" max="max}'; }
drv(){ [ -d "$PS" ] && echo intel_pstate || cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_driver 2>/dev/null; }
cst_off(){ n=0; for f in /sys/devices/system/cpu/cpu*/cpuidle/state[1-9]*/disable; do [ "$(cat $f 2>/dev/null)" = 1 ] && n=$((n+1)); done; echo "$n"; }

do_max(){
  echo performance | tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor >/dev/null 2>&1
  if [ -d "$PS" ]; then echo 100 > "$PS/min_perf_pct" 2>/dev/null; echo 0 > "$PS/no_turbo" 2>/dev/null
  else for c in /sys/devices/system/cpu/cpu*/cpufreq; do cat "$c/scaling_max_freq" > "$c/scaling_min_freq" 2>/dev/null; done
       echo 1 > /sys/devices/system/cpu/cpufreq/boost 2>/dev/null; fi
  # не давать ядрам засыпать -> сидят в C0 на макс, разгон не нужен (мгновенный удар по cuckoo)
  for f in /sys/devices/system/cpu/cpu*/cpuidle/state[1-9]*/disable; do echo 1 > "$f" 2>/dev/null; done
  if msr_ok; then v=$("$RD" -p 0 0x1fc 2>/dev/null); [ -n "$v" ] && "$WR" -a 0x1fc $(( 0x$v | 0x80000 )) 2>/dev/null && EET="+EET off"; fi
  echo ">>> MAX: performance + min=max + C-states OFF + турбо вкл ${EET}"
  freqs
}
do_normal(){
  for g in schedutil ondemand powersave; do echo $g 2>/dev/null | tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor >/dev/null 2>&1; grep -qx "$g" /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null && break; done
  if [ -d "$PS" ]; then echo 20 > "$PS/min_perf_pct" 2>/dev/null
  else for c in /sys/devices/system/cpu/cpu*/cpufreq; do cat "$c/cpuinfo_min_freq" > "$c/scaling_min_freq" 2>/dev/null; done; fi
  for f in /sys/devices/system/cpu/cpu*/cpuidle/state[1-9]*/disable; do echo 0 > "$f" 2>/dev/null; done
  if msr_ok; then v=$("$RD" -p 0 0x1fc 2>/dev/null); [ -n "$v" ] && "$WR" -a 0x1fc $(( 0x$v & ~0x80000 )) 2>/dev/null; fi
  echo ">>> NORMAL: динамический governor + C-states ВКЛ + EET ВКЛ (штатно, как до max)"
  freqs
}
do_status(){
  echo "драйвер: $(drv)"
  echo "governor:$(cat /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor 2>/dev/null | sort | uniq -c | tr '\n' ' ')"
  [ -d "$PS" ] && echo "min_perf_pct=$(cat $PS/min_perf_pct 2>/dev/null)  no_turbo=$(cat $PS/no_turbo 2>/dev/null)"
  echo "C-states отключено на нитях: $(cst_off)"
  if msr_ok; then v=$("$RD" -p 0 0x1fc 2>/dev/null); [ -n "$v" ] && { b=$(( (0x$v>>19)&1 )); echo "EET: $([ $b = 1 ] && echo OFF || echo ON)  (0x1fc=$v)"; }; else echo "MSR: недоступен"; fi
  freqs
}
case "$MODE" in
  max) do_max ;;
  normal|norm) do_normal ;;
  *) do_status ;;
esac
