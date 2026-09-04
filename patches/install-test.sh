#!/bin/bash
# Установка тест-пакета testgc (фейк-нода, замер CPU/GPU). Запуск:
#   ... | TK=ghp_ВАШ_ТОКЕН bash          (распакует в /home/testgc)
#   ... | TK=ghp_ВАШ_ТОКЕН DEST=/opt bash (в другое место)
TK="${TK:?передай токен: ... | TK=ghp_ВАШ_ТОКЕН bash}"
DEST="${DEST:-/home}"
curl -sfL -H "Authorization: token $TK" -H "Accept: application/vnd.github.raw" "https://api.github.com/repos/slot-ekb/My-reload/contents/testgc.tar.gz" -o /tmp/testgc.tar.gz || { echo "СКАЧИВАНИЕ НЕ УДАЛОСЬ"; exit 1; }
mkdir -p "$DEST" && tar xzf /tmp/testgc.tar.gz -C "$DEST" || { echo "РАСПАКОВКА НЕ УДАЛАСЬ"; exit 1; }
chmod +x "$DEST/testgc"/*.sh
echo "готово -> $DEST/testgc"
echo "описание:  cat $DEST/testgc/README.txt"
echo "пример:    cd $DEST/testgc && ./sharecpu.sh 30 8   |   ./sharegpu.sh 30 6"
