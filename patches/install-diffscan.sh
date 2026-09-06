#!/bin/bash
# ЧИСТАЯ (пере)установка diffscan (распределение веса шар). Боевое/testgc/sweep не трогает.
#   ... | bash            -> в /home/diffscan
#   ... | DEST=/opt bash  -> в другое место
DEST="${DEST:-/home}"
curl -sfL "https://raw.githubusercontent.com/slot-ekb/My-reload/main/diffscan.tar.gz" -o /tmp/diffscan.tar.gz || { echo "СКАЧИВАНИЕ НЕ УДАЛОСЬ"; exit 1; }
[ -x "$DEST/diffscan/stop.sh" ] && "$DEST/diffscan/stop.sh" 2>/dev/null
pkill -f "$DEST/diffscan/" 2>/dev/null; sleep 1
rm -rf "$DEST/diffscan"
mkdir -p "$DEST" && tar xzf /tmp/diffscan.tar.gz -C "$DEST" || { echo "РАСПАКОВКА НЕ УДАЛАСЬ"; exit 1; }
chmod +x "$DEST/diffscan"/*.sh "$DEST/diffscan"/*.py "$DEST/diffscan/bin"/* 2>/dev/null
echo "готово -> $DEST/diffscan"
echo "запуск:  cd $DEST/diffscan && ./diffscan.sh 60 4 1 1"
