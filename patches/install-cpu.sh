#!/bin/bash
# ЧИСТАЯ (пере)установка CPU-пакета: сносит старый /opt/proxycpu1 и ставит заново.
# GPU-пакет (/opt/proxygpu1) НЕ трогает. Запуск:
#   ... | NODE=ip:port bash
NODE="${NODE:?передай адрес ноды: ... | NODE=ip:port bash}"
RAW=https://raw.githubusercontent.com/slot-ekb/My-reload/main
dl(){ curl -sfL "$RAW/$1" -o "$2"; }
dl proxycpu1.tar.gz /tmp/proxycpu1.tar.gz || { echo "СКАЧИВАНИЕ НЕ УДАЛОСЬ"; exit 1; }
# погасить и снести старое (только CPU-пакет)
/opt/proxycpu1/all-stop.sh 2>/dev/null; pkill -f /opt/proxycpu1/ 2>/dev/null; sleep 1
rm -rf /opt/proxycpu1
mkdir -p /opt && tar xzf /tmp/proxycpu1.tar.gz -C /opt || { echo "РАСПАКОВКА НЕ УДАЛАСЬ"; exit 1; }
chmod +x /opt/proxycpu1/*.sh
sed -i "s|^NODE=.*|NODE=\"$NODE\"|" /opt/proxycpu1/config.env
echo "чисто установлено в /opt/proxycpu1, NODE=$NODE (WORKERS=$(grep -oE '^WORKERS=[0-9]+' /opt/proxycpu1/config.env), USE_PROXY=$(grep -oE '^USE_PROXY=[a-z]+' /opt/proxycpu1/config.env))"
/opt/proxycpu1/all-start.sh
