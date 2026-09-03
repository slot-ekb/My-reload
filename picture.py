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

recv_h = {}     # height -> IP пира, от кого получили (напрямую из строки)
recv_t = {}     # height -> время получения
acc = {}        # height -> (time, hash)   принят нодой
rx_recv = re.compile(r'(\d\d:\d\d:\d\d\.\d+) .*Received block \w+ at (\d+) from ([\d.]+:\d+)')
rx_acc  = re.compile(r'(\d\d:\d\d:\d\d\.\d+) .*block_accepted \((?:head\+|fork\?)\): (\w+) at (\d+)')
files = sorted([f for f in glob.glob(LOG + ".*")], reverse=True) + [LOG]
for fn in files:
    try:
        for line in open(fn, errors='replace'):
            m = rx_recv.search(line)
            if m:
                h = int(m.group(2))
                if h not in recv_h: recv_h[h] = m.group(3); recv_t[h] = m.group(1)
            m = rx_acc.search(line)
            if m:
                acc[int(m.group(3))] = (m.group(1), m.group(2))
    except: pass
print(f"файлов лога прочитано: {len(files)}")

def src(height):
    if height in recv_h:                       # получен от пира — есть IP
        return (recv_t[height], recv_h[height])
    if height in acc:                          # принят, но не получен от пира = намайнили сами
        return (acc[height][0], ">>> МЫ ВЗЯЛИ <<<")
    return ("?", "нет данных (вне лога)")

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
pre_src = Counter(src(ch-1)[1] for ch in cuckoos if src(ch-1)[1][0:1].isdigit())
if pre_src:
    print("кто чаще приносит pre-блок (перед cuckoo):")
    for p, c in pre_src.most_common(): print(f"   {c}x  {p}")
