#!/bin/bash
# Обновляет ТОЛЬКО GPU-пакет (/opt/proxygpu1). CPU не трогает.
# 2 процесса на карту, прямо на ноду. CPU на этом риге — отдельно через apply-cpu.
dl(){ curl -sfL "https://raw.githubusercontent.com/slot-ekb/My-reload/main/patches/$1" -o "$2"; }
[ -d /opt/proxygpu1 ] || { echo "нет /opt/proxygpu1 — сначала поставь GPU-пакет"; exit 1; }
dl proxygpu1-miners-start.sh /opt/proxygpu1/miners-start.sh || { echo "СКАЧ miners-start НЕ УДАЛОСЬ"; exit 1; }
head -1 /opt/proxygpu1/miners-start.sh | grep -q '#!/bin/bash' || { echo "ФАЙЛ БИТЫЙ"; exit 1; }
dl proxygpu1-all-start.sh /opt/proxygpu1/all-start.sh || true
chmod +x /opt/proxygpu1/miners-start.sh /opt/proxygpu1/all-start.sh
grep -q '^PROC_PER_GPU=' /opt/proxygpu1/config.env || echo 'PROC_PER_GPU=2' >> /opt/proxygpu1/config.env
sed -i 's/^PROC_PER_GPU=.*/PROC_PER_GPU=2/' /opt/proxygpu1/config.env
grep -q '^USE_PROXY=' /opt/proxygpu1/config.env || echo 'USE_PROXY=off' >> /opt/proxygpu1/config.env
/opt/proxygpu1/miners-stop.sh; sleep 2; /opt/proxygpu1/miners-start.sh
