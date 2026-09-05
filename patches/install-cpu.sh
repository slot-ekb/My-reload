#!/bin/bash
# Чистая установка CPU-пакета на новый риг (без GPU). Запуск:
#   ... | TK=ghp_ВАШ_ТОКЕН NODE=ip:port bash
NODE="${NODE:?передай адрес ноды: ... | NODE=ip:port bash}"
RAW=https://raw.githubusercontent.com/slot-ekb/My-reload/main
dl(){ curl -sfL "$RAW/$1" -o "$2"; }
dl proxycpu1.tar.gz /tmp/proxycpu1.tar.gz || { echo "СКАЧИВАНИЕ НЕ УДАЛОСЬ"; exit 1; }
mkdir -p /opt && tar xzf /tmp/proxycpu1.tar.gz -C /opt || { echo "РАСПАКОВКА НЕ УДАЛАСЬ"; exit 1; }
chmod +x /opt/proxycpu1/*.sh
sed -i "s|^NODE=.*|NODE=\"$NODE\"|" /opt/proxycpu1/config.env
echo "установлено в /opt/proxycpu1, NODE=$NODE, INSTANCES=$(grep -oE '^INSTANCES=[0-9]+' /opt/proxycpu1/config.env)"
/opt/proxycpu1/miners-stop.sh 2>/dev/null; sleep 1
/opt/proxycpu1/miners-start.sh
