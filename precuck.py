#!/usr/bin/env python3
# precuck.py — кто ПЕРВЫМ приносит pre-cuckoo randomx (высоты ...03/28/53/78 = height%25==3).
# Рейтинг пиров: кто чаще всех первый = тех и держать/пинить.
import re, os, glob, sys
LOG = sys.argv[1] if len(sys.argv) > 1 else None
if not LOG:
    g = glob.glob(os.path.expanduser("~/.epic/main/epic-server.log")) or \
        glob.glob(os.path.expanduser("~/.epic/**/epic-server.log"), recursive=True)
    LOG = g[0] if g else None
if not LOG or not os.path.isfile(LOG):
    print("нет epic-server.log — укажи путь: python3 precuck.py /path/to/epic-server.log"); sys.exit(1)

first = {}   # height -> (time, peer)
rx = re.compile(r'(\d\d:\d\d:\d\d\.\d+) .*Received block header \w+ at (\d+) from ([\d.]+:\d+)')
for line in open(LOG, errors='replace'):
    m = rx.search(line)
    if not m: continue
    tm, h, peer = m.group(1), int(m.group(2)), m.group(3)
    if h % 25 != 3: continue            # только pre-cuckoo (перед cuckoo, что на %25==4)
    if h not in first:                   # лог хронологический -> первое вхождение = первый доставивший
        first[h] = (tm, peer)

print(f"лог: {LOG}")
print(f"pre-cuckoo блоков в логе: {len(first)}\n")
print("по каждому — КТО первый:")
counts = {}
for h in sorted(first):
    tm, peer = first[h]
    print(f"  h={h}  первый: {peer:22s} в {tm}")
    counts[peer] = counts.get(peer, 0) + 1
print("\n=== РЕЙТИНГ: кто чаще первый на pre-cuckoo randomx (их и пинить) ===")
for peer, c in sorted(counts.items(), key=lambda x: -x[1]):
    print(f"  {c:3d}x   {peer}")
