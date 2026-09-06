#!/bin/bash
# ЧИСТАЯ (пере)установка тест-пакета testgc: гасит старый тест, сносит папку, ставит заново.
# Боевое (/opt/proxycpu1, /opt/proxygpu1) НЕ трогает. Запуск:
#   ... | bash            -> в /home/testgc
#   ... | DEST=/opt bash  -> в другое место
DEST="${DEST:-/home}"
curl -sfL "https://raw.githubusercontent.com/slot-ekb/My-reload/main/testgc.tar.gz" -o /tmp/testgc.tar.gz || { echo "СКАЧИВАНИЕ НЕ УДАЛОСЬ"; exit 1; }
# погасить старый тест и снести папку (только тест по его пути)
[ -x "$DEST/testgc/mstop.sh" ] && "$DEST/testgc/mstop.sh" 2>/dev/null
pkill -f "$DEST/testgc/" 2>/dev/null; sleep 1
rm -rf "$DEST/testgc"
mkdir -p "$DEST" && tar xzf /tmp/testgc.tar.gz -C "$DEST" || { echo "РАСПАКОВКА НЕ УДАЛАСЬ"; exit 1; }
chmod +x "$DEST/testgc"/*.sh
echo "чисто установлено -> $DEST/testgc"
echo "описание:  cat $DEST/testgc/README.txt"
echo "пример:    cd $DEST/testgc && ./mtest.sh cpu 14 4 60   (=боевой WORKERS=14 INSTANCES=4)"
