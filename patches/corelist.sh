#!/bin/bash
# Заполняет CORES[] — ФИЗИЧЕСКИЕ ядра по порядку, каждое = его логич.CPU через запятую
# (напр. "0,36" = ядро с двумя HT-потоками), и NCORE — число физ.ядер.
# От нумерации/HT не зависит (через lscpu). Фолбэк: 1 CPU = 1 "ядро".
CORES=(); NCORE=0
if command -v lscpu >/dev/null 2>&1; then
  declare -A _cm; _ord=()
  while IFS=, read -r _cpu _core; do
    [ -z "$_cpu" ] && continue
    if [ -z "${_cm[$_core]:-}" ]; then _ord+=("$_core"); _cm[$_core]="$_cpu"; else _cm[$_core]="${_cm[$_core]},$_cpu"; fi
  done < <(lscpu -p=CPU,CORE 2>/dev/null | grep -v '^#')
  for _c in "${_ord[@]}"; do CORES+=("${_cm[$_c]}"); done
fi
[ "${#CORES[@]}" -lt 1 ] && for ((_i=0;_i<$(nproc);_i++)); do CORES+=("$_i"); done
NCORE=${#CORES[@]}
