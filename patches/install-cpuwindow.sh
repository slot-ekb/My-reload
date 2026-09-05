#!/bin/bash
# Ставит cpuwindow в /opt/cpuwindow и запускает в screen "cpuwin".
curl -sfL "https://raw.githubusercontent.com/slot-ekb/My-reload/main/cpuwindow.tar.gz" -o /tmp/cpuwindow.tar.gz || { echo "СКАЧ НЕ УДАЛОСЬ"; exit 1; }
mkdir -p /opt && tar xzf /tmp/cpuwindow.tar.gz -C /opt || { echo "РАСПАКОВКА НЕ УДАЛАСЬ"; exit 1; }
chmod +x /opt/cpuwindow/*.sh /opt/cpuwindow/*.py /opt/cpuwindow/bin/* 2>/dev/null
/opt/cpuwindow/cw-start.sh
