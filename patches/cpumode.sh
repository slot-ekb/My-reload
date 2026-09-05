#!/bin/bash
# cpumode.sh — режимы частоты CPU БЕЗ установки (чистый sysfs; MSR только если есть).
#   max     — держать ядра ВСЕГДА на максимуме (governor=perf, min=max, C-states OFF,
#             турбо вкл, EET off). Мгновенный отклик на коротком cuckoo-окне.
#   normal  — вернуть как было (schedutil/ondemand, C-states вкл, EET вкл).
#   status  — показать текущее состояние.
MODE="${1:-status}"
PS=/sys/devices/system/cpu/intel_pstate
have(){ command -v "$1" >/dev/null 2>&1; }

freqs(){ grep MHz /proc/cpuinfo | awk '{printf "%.0f\n",$4}' | sort -n | awk 'NR==1{min=$1}{max=$1}END{print "  частоты MHz: min="min" max="max}'; }
drv(){ [ -d "$PS" ] && echo intel_pstate || cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_driver 2>/dev/null; }
cstates_off(){ ls /sys/devices/system/cpu/cpu0/cpuidle/state1/disable >/dev/null 2>&1 && { n=0; for f in /sys/devices/system/cpu/cpu*/cpuidle/state[1-9]*/disable; do [ "$(cat $f 2>/dev/null)" = 1 ] && n=$((n+1)); done; echo "$n"; } || echo "?"; }

do_max(){
  echo performance | tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor >/dev/null 2>&1
  if [ -d "$PS" ]; then
    echo 100 > "$PS/min_perf_pct" 2>/dev/null; echo 0 > "$PS/no_turbo" 2>/dev/null
  else
    for c in /sys/devices/system/cpu/cpu*/cpufreq; do cat "$c/scaling_max_freq" > "$c/scaling_min_freq" 2>/dev/null; done
    echo 1 > /sys/devices/system/cpu/cpufreq/boost 2>/dev/null
  fi
  # НЕ давать ядрам засыпать -> держатся в C0 на макс, разгон не нужен (мгновенный удар по cuckoo)
  for f in /sys/devices/system/cpu/cpu*/cpuidle/state[1-9]*/disable; do echo 1 > "$f" 2>/dev/null; done
  # MSR (если есть): выключить Energy Efficient Turbo (бит19 MSR 0x1FC)
  if have wrmsr && have rdmsr; then modprobe msr 2>/dev/null
    v=$(rdmsr -p 0 0x1fc 2>/dev/null)
    [ -n "$v" ] && wrmsr -a 0x1fc $(( 0x$v | 0x80000 )) 2>/dev/null && EET="EET off"
  fi
  echo ">>> MAX: performance + min=max + C-states OFF + турбо вкл ${EET:+(+ $EET)}"
  freqs
}

do_normal(){
  for g in schedutil ondemand powersave; do echo $g 2>/dev/null | tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor >/dev/null 2>&1 && grep -qx "$g" /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null && break; done
  [ -d "$PS" ] && echo 20 > "$PS/min_perf_pct" 2>/dev/null
  [ ! -d "$PS" ] && for c in /sys/devices/system/cpu/cpu*/cpufreq; do cat "$c/cpuinfo_min_freq" > "$c/scaling_min_freq" 2>/dev/null; done
  for f in /sys/devices/system/cpu/cpu*/cpuidle/state[1-9]*/disable; do echo 0 > "$f" 2>/dev/null; done
  if have wrmsr && have rdmsr; then v=$(rdmsr -p 0 0x1fc 2>/dev/null); [ -n "$v" ] && wrmsr -a 0x1fc $(( 0x$v & ~0x80000 )) 2>/dev/null; fi
  echo ">>> NORMAL: динамический governor, C-states вкл, EET вкл"
  freqs
}

do_status(){
  echo "драйвер: $(drv)"
  echo "governor: $(cat /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor 2>/dev/null | sort | uniq -c | tr -s ' ')"
  [ -d "$PS" ] && echo "min_perf_pct=$(cat $PS/min_perf_pct 2>/dev/null)  no_turbo=$(cat $PS/no_turbo 2>/dev/null)"
  echo "C-states отключено на нитях: $(cstates_off)"
  if have rdmsr; then v=$(rdmsr -p 0 0x1fc 2>/dev/null); [ -n "$v" ] && { b=$(( (0x$v>>19)&1 )); echo "EET: $([ $b = 1 ] && echo OFF || echo ON) (0x1fc=$v)"; }; fi
  freqs
}

case "$MODE" in
  max) do_max ;;
  normal|norm) do_normal ;;
  *) do_status ;;
esac
