#!/bin/bash
# Обновляет ТОЛЬКО прокси (epic_proxy.py + proxy-start.sh) в /opt/proxycpu1 и/или /opt/proxygpu1.
# CPU/GPU-пакеты и майнеров НЕ трогает. Добавляет NODE2 в config (пусто).
# Мультинода: задание берётся ТОЛЬКО с NODE (основная), submit шлётся на NODE и NODE2.
# ВАЖНО: NODE2 должна быть на ТОЙ ЖЕ цепи (иначе чужая нода отвергнет шару).
dl(){ curl -sfL "https://raw.githubusercontent.com/slot-ekb/My-reload/main/patches/$1" -o "$2"; }
any=0
for pkg in proxycpu1 proxygpu1; do
  D=/opt/$pkg; [ -d "$D" ] || continue
  dl epic_proxy.py "$D/bin/epic_proxy.py" || { echo "$pkg: СКАЧ epic_proxy НЕ УДАЛОСЬ"; continue; }
  head -1 "$D/bin/epic_proxy.py" | grep -q 'python3' || { echo "$pkg: epic_proxy битый"; continue; }
  dl "$pkg-proxy-start.sh" "$D/proxy-start.sh" || { echo "$pkg: СКАЧ proxy-start НЕ УДАЛОСЬ"; continue; }
  chmod +x "$D/proxy-start.sh" "$D/bin/epic_proxy.py"
  grep -q '^NODE2=' "$D/config.env" || echo 'NODE2=""' >> "$D/config.env"
  echo "$pkg: прокси обновлён (NODE=$(grep -oE '^NODE=\"[^\"]*\"' "$D/config.env"), NODE2=$(grep -oE '^NODE2=\"[^\"]*\"' "$D/config.env"))"
  up=$(grep -oE '^USE_PROXY=[a-z]+' "$D/config.env" | grep -oE '[a-z]+$')
  if [ "$up" = on ]; then "$D/proxy-start.sh"; else
    echo "  USE_PROXY=off — майнеры идут мимо прокси. Чтобы задействовать 2 ноды: включи USE_PROXY=on и перезапусти майнеры (это уже действие пакета)."
  fi
  any=1
done
[ "$any" = 1 ] || echo "нет ни /opt/proxycpu1, ни /opt/proxygpu1"
echo "Задать 2-ю ноду:  sed -i 's/^NODE2=.*/NODE2=\"ip:port\"/' /opt/proxycpu1/config.env  (та же цепь!)  затем /opt/proxycpu1/proxy-start.sh"
