#!/bin/bash
# Портативно вычисляет cpuset: ПОСЛЕДНИЕ G физ.ядер -> GPU, всё остальное -> CPU.
# Работает на любой плате (с HyperThreading и без), не зависит от нумерации ядер.
#   . aff.sh [G]     -> выставит переменные $GPUSET и $CPUSET (для использования в скрипте)
#   bash aff.sh [G]  -> просто покажет, что получится
# G = сколько ФИЗИЧЕСКИХ ядер отдать под карты (по умолчанию 6).
G="${1:-6}"

mapfile -t rows < <(lscpu -p=CPU,CORE 2>/dev/null | grep -v '^#')
cores=$(printf '%s\n' "${rows[@]}" | awk -F, '{print $2}' | awk '!seen[$0]++')
ncore=$(echo "$cores" | grep -c .)
[ "$G" -gt "$ncore" ] && G=$ncore
gpu_cores=$(echo "$cores" | tail -n "$G")

gpu_cpus=""; cpu_cpus=""
for r in "${rows[@]}"; do
  cpu=${r%%,*}; core=${r##*,}
  if echo "$gpu_cores" | grep -qx "$core"; then gpu_cpus+="$cpu "; else cpu_cpus+="$cpu "; fi
done
GPUSET=$(echo $gpu_cpus | tr ' ' '\n' | sort -n | paste -sd,)
CPUSET=$(echo $cpu_cpus | tr ' ' '\n' | sort -n | paste -sd,)
export GPUSET CPUSET
echo "физ.ядер: $ncore | под GPU последние $G | логич.нитей всего: $(nproc)"
echo "GPUSET=$GPUSET   (карты)"
echo "CPUSET=$CPUSET   (CPU-куку — тут сам задаёшь сколько воркеров)"
