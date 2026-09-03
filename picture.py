#!/usr/bin/env python3
# picture.py — широкая картина: последние блоки, КТО отдал каждый (или "МЫ НАШЛИ"),
# пометка CUCKOO, и сколько cuckoo мы реально поймали.
# "МЫ НАШЛИ" = блок принят нодой (block_accepted head+), но НЕ было "Received ... from <peer>".
import re, os, glob, sys
LOG = sys.argv[1] if len(sys.argv) > 1 else None
if not LOG:
    g = glob.glob(os.path.expanduser("~/.epic/main/epic-server.log")) or \
        glob.glob(os.path.expanduser("~/.epic/**/epic-server.log"), recursive=True)
    LOG = g[0] if g else None
if not LOG or not os.path.isfile(LOG):
    print("нет epic-server.log"); sys.exit(1)

received = {}   # hash -> первый пир, от кого получили
accepted = []   # (time, hash, height)
rx_recv = re.compile(r'Received block (\w+) at (\d+) from ([\d.]+:\d+)')
rx_acc  = re.compile(r'(\d\d:\d\d:\d\d\.\d+) .*block_accepted \((?:head\+|fork\?)\): (\w+) at (\d+)')
for line in open(LOG, errors='replace'):
    m = rx_recv.search(line)
    if m and m.group(1) not in received:
        received[m.group(1)] = m.group(3)
    m = rx_acc.search(line)
    if m:
        accepted.append((m.group(1), m.group(2), int(m.group(3))))

print(f"лог: {LOG}\nпоследние блоки:")
for tm, h, height in accepted[-40:]:
    cuck = (height % 25 == 4)
    if h in received:
        src = "от " + received[h]
    else:
        src = ">>> МЫ НАШЛИ <<<"
    mark = "  *** CUCKOO ***" if cuck else ""
    print(f"  h={height}  {src:32s}{mark}  ({tm})")

mine = [a for a in accepted if a[1] not in received]
cuck_all = [a for a in accepted if a[2] % 25 == 4]
cuck_mine = [a for a in mine if a[2] % 25 == 4]
print(f"\nвсего блоков принято: {len(accepted)}")
print(f"из них НАШИХ (намайнили сами): {len(mine)}")
print(f"cuckoo всего в логе: {len(cuck_all)}  |  из них НАШИХ cuckoo: {len(cuck_mine)}")
for tm, h, height in cuck_mine:
    print(f"   НАШ CUCKOO  h={height}  в {tm}")
