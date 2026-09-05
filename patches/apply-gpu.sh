#!/bin/bash
TK="${TK:?передай токен так: ... | TK=ghp_ВАШ_ТОКЕН bash}"
dl(){ curl -sfL -H "Authorization: token $TK" -H "Accept: application/vnd.github.raw" "https://api.github.com/repos/slot-ekb/My-reload/contents/patches/$1" -o "$2"; }
for p in proxygpu1 proxycpu1; do
  dl "$p-miners-start.sh" "/opt/$p/miners-start.sh" || { echo "СКАЧ $p НЕ УДАЛОСЬ"; exit 1; }
  head -1 "/opt/$p/miners-start.sh" | grep -q '#!/bin/bash' || { echo "ФАЙЛ $p БИТЫЙ"; exit 1; }
  dl "$p-all-start.sh" "/opt/$p/all-start.sh" || true
  chmod +x "/opt/$p/miners-start.sh" "/opt/$p/all-start.sh"
  grep -q '^PROC_PER_GPU=' "/opt/$p/config.env" || echo 'PROC_PER_GPU=2' >> "/opt/$p/config.env"
  sed -i 's/^PROC_PER_GPU=.*/PROC_PER_GPU=2/' "/opt/$p/config.env"
  grep -q '^USE_PROXY=' "/opt/$p/config.env" || echo 'USE_PROXY=off' >> "/opt/$p/config.env"
done
sed -i 's/^INSTANCES=.*/INSTANCES=2/' /opt/proxycpu1/config.env
/opt/proxycpu1/miners-stop.sh; /opt/proxygpu1/miners-stop.sh; sleep 2
/opt/proxygpu1/miners-start.sh; sleep 3; /opt/proxycpu1/miners-start.sh
