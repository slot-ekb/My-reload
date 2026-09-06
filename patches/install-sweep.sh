#!/bin/bash
# ЧИСТАЯ (пере)установка sweep (замер nthreads для одного солвера). Боевое/testgc не трогает.
#   ... | bash            -> в /home/sweep
#   ... | DEST=/opt bash  -> в другое место
DEST="${DEST:-/home}"
curl -sfL "https://raw.githubusercontent.com/slot-ekb/My-reload/main/sweep.tar.gz" -o /tmp/sweep.tar.gz || { echo "СКАЧИВАНИЕ НЕ УДАЛОСЬ"; exit 1; }
[ -x "$DEST/sweep/stop.sh" ] && "$DEST/sweep/stop.sh" 2>/dev/null
pkill -f "$DEST/sweep/" 2>/dev/null; sleep 1
rm -rf "$DEST/sweep"
mkdir -p "$DEST" && tar xzf /tmp/sweep.tar.gz -C "$DEST" || { echo "РАСПАКОВКА НЕ УДАЛАСЬ"; exit 1; }
chmod +x "$DEST/sweep"/*.sh "$DEST/sweep"/*.py "$DEST/sweep/bin"/* 2>/dev/null
echo "готово -> $DEST/sweep"
echo "запуск:  cd $DEST/sweep && ./sweep.sh 40 \"1 2 4 6 8\""
