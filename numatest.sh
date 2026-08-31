#!/bin/bash
# Один тест: поднимает фейк, гоняет N секунд, мерит g/s, ВСЁ выключает.
# Использование: ./numatest.sh [numa|nonuma] [секунды]
cd "$(dirname "$0")"
MODE=${1:-numa}; SECS=${2:-40}
[ "$MODE" = "nonuma" ] && NF=0 || NF=1

# старт фейк-ноды (непрерывная ку-ку нагрузка)
pkill -f "fakestratum.py" 2>/dev/null; sleep 1
python3 fakestratum.py >/tmp/fake.log 2>&1 &
sleep 2

# запуск воркеров на фейк
export STRAT_OVERRIDE="127.0.0.1:3499"
NUMA=$NF ./run-auto.sh >/dev/null 2>&1

echo ">>> тест: $MODE, жду ${SECS}с (фейк даёт ку-ку непрерывно)..."
sleep "$SECS"

echo ">>> РЕЗУЛЬТАТ ($MODE):"
bash hr.sh

# выключить всё, что использовал тест
./stop.sh >/dev/null 2>&1
pkill -f epic-miner 2>/dev/null
pkill -f "fakestratum.py" 2>/dev/null
rm -rf inst 2>/dev/null
echo ">>> всё выключено (воркеры + фейк)"
