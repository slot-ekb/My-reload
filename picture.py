#!/usr/bin/env python3
# picture.py — ТОЛЬКО cuckoo (высота %25==4) + один блок перед ним, по ВСЕМУ логу.
# По каждому cuckoo: взяли ли МЫ или кто отдал; и кто отдал pre-блок (перед ним).
import re, os, glob, sys
LOG = sys.argv[1] if len(sys.argv) > 1 else None
if not LOG:
    g = glob.glob(os.path.expanduser("~/.epic/main/epic-server.log")) or \
        glob.glob(os.path.expanduser("~/.epic/**/epic-server.log"), recursive=True)
    LOG = g[0] if g else None
if not LOG or not os.path.isfile(LOG):
    print("нет epic-server.log"); sys.exit(1)

received = {}   # hash -> первый пир
acc = {}        # height -> (time, hash)   последний accepted на высоте
rx_recv = re.compile(r'Received block (\w+) at (\d+) from ([\d.]+:\d+)')
rx_acc  = re.compile(r'(\d\d:\d\d:\d\d\.\d+) .*block_accepted \((?:head\+|fork\?)\): (\w+) at (\d+)')
# читаем старые ротированные файлы (.1, .2 ...) от старых к новым, потом текущий
files = sorted([f for f in glob.glob(LOG + ".*")], reverse=True) + [LOG]
for fn in files:
    try:
        for line in open(fn, errors='replace'):
            m = rx_recv.search(line)
            if m and m.group(1) not in received:
                received[m.group(1)] = m.group(3)
            m = rx_acc.search(line)
            if m:
                acc[int(m.group(3))] = (m.group(1), m.group(2))
    except: pass
print(f"файлов лога прочитано: {len(files)}")

def src(height):
    if height not in acc: return ("?", "нет данных")
    tm, h = acc[height]
    return (tm, ">>> МЫ ВЗЯЛИ <<<" if h not in received else received[h])

cuckoos = sorted(hh for hh in acc if hh % 25 == 4)
print(f"лог: {LOG}")
print(f"CUCKOO в логе: {len(cuckoos)}\n")
won = 0
for ch in cuckoos:
    ctm, cs = src(ch); ptm, ps = src(ch - 1)
    star = "   ★★★ НАШ ★★★" if "ВЗЯЛИ" in cs else ""
    if "ВЗЯЛИ" in cs: won += 1
    print(f"CUCKOO h={ch}  [{cs}]  {ctm}{star}")
    print(f"   pre-блок h={ch-1}  от {ps}  {ptm}")
print(f"\n==== ИТОГ: cuckoo всего {len(cuckoos)}, ВЗЯЛИ мы {won} ({100*won//max(len(cuckoos),1)}%) ====")
# кто чаще отдаёт pre-блок (перед cuckoo) — их пинить
from collections import Counter
pre_src = Counter(src(ch-1)[1] for ch in cuckoos if src(ch-1)[1] not in ("нет данных",">>> МЫ ВЗЯЛИ <<<"))
if pre_src:
    print("кто чаще приносит pre-блок (перед cuckoo):")
    for p, c in pre_src.most_common(): print(f"   {c}x  {p}")
