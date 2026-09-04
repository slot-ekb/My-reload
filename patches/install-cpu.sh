#!/bin/bash
# Чистая установка CPU-пакета на новый риг (без GPU). Запуск:
#   ... | TK=ghp_ВАШ_ТОКЕН NODE=ip:port bash
TK="${TK:?передай токен: ... | TK=ghp_ВАШ_ТОКЕН NODE=ip:port bash}"
NODE="${NODE:?передай адрес ноды: ... | TK=... NODE=ip:port bash}"
dl(){ curl -sfL -H "Authorization: token $TK" -H "Accept: application/vnd.github.raw" "https://api.github.com/repos/slot-ekb/My-reload/contents/$1" -o "$2"; }
dl proxycpu1.tar.gz /tmp/proxycpu1.tar.gz || { echo "СКАЧИВАНИЕ НЕ УДАЛОСЬ"; exit 1; }
mkdir -p /opt && tar xzf /tmp/proxycpu1.tar.gz -C /opt || { echo "РАСПАКОВКА НЕ УДАЛАСЬ"; exit 1; }
chmod +x /opt/proxycpu1/*.sh
sed -i "s|^NODE=.*|NODE=\"$NODE\"|" /opt/proxycpu1/config.env
echo "установлено в /opt/proxycpu1, NODE=$NODE, INSTANCES=$(grep -oE '^INSTANCES=[0-9]+' /opt/proxycpu1/config.env)"
/opt/proxycpu1/miners-stop.sh 2>/dev/null; sleep 1
/opt/proxycpu1/miners-start.sh
