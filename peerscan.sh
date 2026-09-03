#!/bin/bash
# Кто отдаёт блоки ноде: cuckoo, pre-cuckoo, и топ-пиры. Гонять на ОБЕИХ нодах.
LOG=$(find ~/.epic -name 'epic-server.log' 2>/dev/null | head -1)
[ -f "$LOG" ] || { echo "нет epic-server.log — укажи путь вручную"; exit 1; }
echo "хост: $(hostname)   лог: $LOG"
echo "===== CUCKOO (высоты ...04/29/54/79) — кто прислал ====="
grep -aE 'Received block .*at [0-9]*(04|29|54|79) from' "$LOG" | grep -aoE '[0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]+ .*(header )?[0-9a-f]{6,} at [0-9]+ from [0-9.]+:[0-9]+' | tail -40
echo "===== PRE-CUCKOO randomx (высоты ...03/28/53/78) — кто прислал ====="
grep -aE 'Received block .*at [0-9]*(03|28|53|78) from' "$LOG" | grep -aoE '[0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]+ .*(header )?[0-9a-f]{6,} at [0-9]+ from [0-9.]+:[0-9]+' | tail -40
echo "===== ТОП-пиры по числу доставленных заголовков ====="
grep -aE 'Received block header [0-9a-f]+ at [0-9]+ from' "$LOG" | grep -aoE 'from [0-9.]+:[0-9]+' | sort | uniq -c | sort -rn | head -15
