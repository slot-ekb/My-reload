#!/bin/bash
# Обновление epic-miner: фикс сортировки рёбер cuckoo-решения перед submit
# (лечит реджекты "edges not ascending" = потерянные блоки). glibc 2.28 -> 20.04 и 22.04.
URL="https://raw.githubusercontent.com/slot-ekb/My-reload/main/epic-miner"
EXPECT="74a0b332de737bec005d00696e2fb7cc"
D=$(dirname "$(find /opt -name epic-miner -type f 2>/dev/null | head -1)")
[ -z "$D" ] && { echo "НЕ НАЙДЕН epic-miner в /opt"; exit 1; }
echo "пак: $D"
pkill -f epic-miner
cp "$D/epic-miner" "$D/epic-miner.bak.$(date +%s)" && echo "бэкап сделан"
curl -sL -o "$D/epic-miner" "$URL" && chmod +x "$D/epic-miner"
GOT=$(md5sum "$D/epic-miner" | cut -d' ' -f1)
echo "md5: $GOT"
[ "$GOT" = "$EXPECT" ] && echo "OK — заменился, запускай майнер" || echo "ВНИМАНИЕ: md5 не совпал, качни ещё раз"
