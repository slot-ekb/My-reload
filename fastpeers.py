#!/usr/bin/env python3
# fastpeers.py — РЕЙТИНГ пиров по СКОРОСТИ доставки: кто ЧАЩЕ первым приносит нам блок.
# Считает по всем блокам в логе (первый "Received block header ... from <peer>" на каждой высоте).
import re, os, glob, sys
from collections import Counter
LOG = sys.argv[1] if len(sys.argv) > 1 else None
if not LOG:
    g = glob.glob(os.path.expanduser("~/.epic/main/epic-server.log")) or \
        glob.glob(os.path.expanduser("~/.epic/**/epic-server.log"), recursive=True)
    LOG = g[0] if g else None
if not LOG or not os.path.isfile(LOG):
    print("нет epic-server.log"); sys.exit(1)

first = {}      # height -> peer  (кто ПЕРВЫЙ прислал заголовок)
first_all = {}  # height -> [все, кто прислал]  для доли «первый из скольких»
rx = re.compile(r'(\d\d:\d\d:\d\d\.\d+) .*Received block header \w+ at (\d+) from ([\d.]+:\d+)')
files = sorted(glob.glob(LOG + ".*"), reverse=True) + [LOG]   # старые -> новый
for fn in files:
    try:
        for line in open(fn, errors='replace'):
            m = rx.search(line)
            if m:
                h = int(m.group(2)); peer = m.group(3)
                if h not in first: first[h] = peer
                first_all.setdefault(h, set()).add(peer)
    except: pass

total = len(first)
print(f"файлов лога: {len(files)}  |  блоков проанализировано: {total}\n")
print("РЕЙТИНГ по скорости (кто ЧАЩЕ первым приносит блок):")
for peer, cnt in Counter(first.values()).most_common(25):
    print(f"  {cnt:4d}x  ({100*cnt//max(total,1):2d}%)   {peer}")
# сколько пиров в среднем присылают каждый блок (для контекста)
avg = sum(len(v) for v in first_all.values()) / max(len(first_all), 1)
print(f"\nв среднем блок присылают {avg:.1f} пиров; первый — это и есть самый быстрый на тот блок.")
