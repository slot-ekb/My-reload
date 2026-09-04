#!/bin/bash
TK="${TK:?передай токен так: ... | TK=ghp_ВАШ_ТОКЕН bash}"
dl(){ curl -sfL -H "Authorization: token $TK" -H "Accept: application/vnd.github.raw" "https://api.github.com/repos/slot-ekb/My-reload/contents/patches/$1" -o "$2"; }
dl proxycpu1-miners-start.sh /opt/proxycpu1/miners-start.sh || { echo "СКАЧИВАНИЕ НЕ УДАЛОСЬ"; exit 1; }
head -1 /opt/proxycpu1/miners-start.sh | grep -q '#!/bin/bash' || { echo "ФАЙЛ БИТЫЙ"; exit 1; }
chmod +x /opt/proxycpu1/miners-start.sh
grep -q '^PROC_PER_GPU=' /opt/proxycpu1/config.env || echo 'PROC_PER_GPU=2' >> /opt/proxycpu1/config.env
sed -i 's/^INSTANCES=.*/INSTANCES=2/' /opt/proxycpu1/config.env
/opt/proxycpu1/miners-stop.sh; sleep 2; /opt/proxycpu1/miners-start.sh
