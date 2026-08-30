#!/bin/bash
# Обновление epic-miner на ВСЕХ паках в /opt: фикс сортировки рёбер cuckoo перед submit
# (лечит реджекты "edges not ascending" = потерянные блоки). glibc 2.28 -> 20.04 и 22.04.
URL="https://raw.githubusercontent.com/slot-ekb/My-reload/main/epic-miner"
EXPECT="74a0b332de737bec005d00696e2fb7cc"
curl -sL -o /tmp/em "$URL" || { echo "НЕ СКАЧАЛОСЬ"; exit 1; }
GOT=$(md5sum /tmp/em | cut -d' ' -f1)
[ "$GOT" = "$EXPECT" ] || { echo "БИТАЯ ЗАКАЧКА ($GOT), повтори"; exit 1; }
echo "скачан новый бинарник ($GOT)"
pkill -f epic-miner
n=0
for f in $(find /opt -name epic-miner -type f 2>/dev/null); do
  [ -f "$f.orig" ] || cp "$f" "$f.orig"      # сохраняем исходный один раз (для отката)
  cp /tmp/em "$f" && chmod +x "$f" && n=$((n+1))
done
echo "обновлено паков: $n"
echo "=== проверка (у всех должно быть $EXPECT) ==="
find /opt -name epic-miner -type f -exec md5sum {} \;
