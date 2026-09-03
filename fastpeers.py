#!/usr/bin/env python3
# fastpeers.py — рейтинг пиров по СКОРОСТИ доставки блоков.
#   "первый" = сколько раз пир раньше всех прислал заголовок блока.
#   "ср.отставание" = в среднем на сколько мс он позже первого (0 = он и есть первый).
import re, os, glob, sys
from collections import Counter, defaultdict
LOG = sys.argv[1] if len(sys.argv) > 1 else None
if not LOG:
    g = glob.glob(os.path.expanduser("~/.epic/main/epic-server.log")) or \
        glob.glob(os.path.expanduser("~/.epic/**/epic-server.log"), recursive=True)
    LOG = g[0] if g else None
if not LOG or not os.path.isfile(LOG):
    print("нет epic-server.log"); sys.exit(1)

def tsec(t):
    hh, mm, ss = t.split(":"); return int(hh)*3600 + int(mm)*60 + float(ss)

times = defaultdict(dict)   # height -> {peer: секунды первого прихода}
rx = re.compile(r'(\d\d:\d\d:\d\d\.\d+) .*Received block header \w+ at (\d+) from ([\d.]+:\d+)')
for fn in sorted(glob.glob(LOG + ".*"), reverse=True) + [LOG]:
    try:
        for line in open(fn, errors='replace'):
            m = rx.search(line)
            if m:
                h = int(m.group(2)); peer = m.group(3); ts = tsec(m.group(1))
                if peer not in times[h]: times[h][peer] = ts
    except: pass

firstc = Counter(); behind = defaultdict(list); deliv = Counter()
for h, pt in times.items():
    mn = min(pt.values()); winner = min(pt, key=pt.get)
    firstc[winner] += 1
    for peer, t in pt.items():
        d = (t - mn) * 1000
        if 0 <= d < 60000:                    # отсекаем мусор (переход суток и т.п.)
            behind[peer].append(d); deliv[peer] += 1

total = len(times)
print(f"блоков: {total}\n")
print("кто ПЕРВЫЙ  | ср.отставание от первого | доставок | пир")
for peer, cnt in firstc.most_common(25):
    b = behind.get(peer, [0]); avg = sum(b)/len(b)
    print(f"  {cnt:4d}x ({100*cnt//max(total,1):2d}%)   {avg:6.0f} мс   {deliv[peer]:4d}   {peer}")
