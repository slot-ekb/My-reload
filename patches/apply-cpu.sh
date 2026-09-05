#!/bin/bash
dl(){ curl -sfL "https://raw.githubusercontent.com/slot-ekb/My-reload/main/patches/$1" -o "$2"; }
dl proxycpu1-miners-start.sh /opt/proxycpu1/miners-start.sh || { echo "СКАЧИВАНИЕ НЕ УДАЛОСЬ"; exit 1; }
head -1 /opt/proxycpu1/miners-start.sh | grep -q '#!/bin/bash' || { echo "ФАЙЛ БИТЫЙ"; exit 1; }
dl proxycpu1-all-start.sh /opt/proxycpu1/all-start.sh || true
chmod +x /opt/proxycpu1/miners-start.sh /opt/proxycpu1/all-start.sh
grep -q '^PROC_PER_GPU=' /opt/proxycpu1/config.env || echo 'PROC_PER_GPU=2' >> /opt/proxycpu1/config.env
grep -q '^USE_PROXY=' /opt/proxycpu1/config.env || echo 'USE_PROXY=off' >> /opt/proxycpu1/config.env
grep -q '^INSTANCES=' /opt/proxycpu1/config.env || echo 'INSTANCES=1' >> /opt/proxycpu1/config.env
grep -q '^NTHREADS='  /opt/proxycpu1/config.env || echo 'NTHREADS=1'  >> /opt/proxycpu1/config.env
/opt/proxycpu1/miners-stop.sh; sleep 2; /opt/proxycpu1/miners-start.sh
