#!/usr/bin/env python3
# peermgr.py — управление пирами ноды НА ЛЕТУ (без рестарта), через API.
#   python3 peermgr.py list        —連connected пиры: высота, версия, направление; отставшие помечены
#   python3 peermgr.py clean [N]    — забанить всех, кто отстал > N высот от вершины (по умолч. 50)
#   python3 peermgr.py ban  IP[:PORT]   — забанить пира
#   python3 peermgr.py unban IP[:PORT]  — разбанить
#   python3 peermgr.py allban       — снять все баны (unban всех known banned)
import urllib.request, urllib.error, json, sys, os, base64

API = os.environ.get("EPIC_API", "http://127.0.0.1:3413")
def secret():
    for p in ("~/.epic/main/.api_secret", "/root/.epic/main/.api_secret"):
        p = os.path.expanduser(p)
        if os.path.isfile(p):
            try: return open(p).read().strip()
            except: pass
    return ""
SEC = secret()
AUTH = "Basic " + base64.b64encode(("epic:" + SEC).encode()).decode() if SEC else None

def api(path, method="GET"):
    req = urllib.request.Request(API + path, method=method)
    if AUTH: req.add_header("Authorization", AUTH)
    try:
        with urllib.request.urlopen(req, timeout=8) as r:
            b = r.read().decode()
            return json.loads(b) if b.strip() else {}
    except urllib.error.HTTPError as e:
        return {"__err": f"HTTP {e.code}"}
    except Exception as e:
        return {"__err": str(e)}

def tip():
    st = api("/v1/status")
    return (st.get("tip", {}) or {}).get("height", 0)

def connected():
    d = api("/v1/peers/connected")
    return d if isinstance(d, list) else d.get("__err") and []

def cmd_list():
    t = tip(); peers = connected()
    print(f"вершина={t}  connected={len(peers)}")
    rows = []
    for p in peers:
        h = p.get("height", 0); addr = p.get("addr", "?"); ua = p.get("user_agent", "")
        dirn = p.get("direction", ""); lag = t - h
        rows.append((lag, h, addr, dirn, ua))
    rows.sort(reverse=True)  # самые отставшие сверху
    for lag, h, addr, dirn, ua in rows:
        flag = "  <== ОТСТАЛ" if lag > 50 else ""
        print(f"  h={h} (lag {lag:+d})  {addr:24s} {dirn:8s} {ua}{flag}")

def cmd_clean(n=50):
    t = tip(); peers = connected(); banned = 0
    for p in peers:
        lag = t - p.get("height", 0)
        if lag > n:
            addr = p.get("addr")
            r = api(f"/v1/peers/{addr}/ban", "POST")
            print(f"  бан {addr} (lag {lag}) -> {r.get('__err','ok')}")
            banned += 1
    print(f"забанено отставших: {banned}")

def cmd_ban(addr):  print(api(f"/v1/peers/{addr}/ban", "POST").get("__err", "ok"))
def cmd_unban(addr): print(api(f"/v1/peers/{addr}/unban", "POST").get("__err", "ok"))

def cmd_scan():
    d = api("/v1/peers/all"); peers = d if isinstance(d, list) else []
    healthy = [p for p in peers if p.get("flags") == "Healthy"]
    banned = [p for p in peers if p.get("flags") == "Banned"]
    print(f"всего известно пиров в сети: {len(peers)} | healthy: {len(healthy)} | banned: {len(banned)}")
    for p in peers:
        a = p.get("addr", "?"); f = p.get("flags", ""); print(f"  {a:24s} {f}")

def learn_fast():
    # САМ учит быстрых из лога: кто был первым доставщиком блока (хоть раз) = защищаем от бана
    import glob as _g
    gg = _g.glob(os.path.expanduser("~/.epic/main/epic-server.log")) or \
         _g.glob(os.path.expanduser("~/.epic/**/epic-server.log"), recursive=True)
    if not gg: return set()
    import re
    from collections import Counter
    base = gg[0]; first = {}
    rx = re.compile(r'Received block header \w+ at (\d+) from ([\d.]+:\d+)')
    for fn in sorted(_g.glob(base + ".*"), reverse=True) + [base]:
        try:
            for line in open(fn, errors='replace'):
                m = rx.search(line)
                if m:
                    h = int(m.group(1))
                    if h not in first: first[h] = m.group(2)
        except: pass
    c = Counter(first.values())
    fast = {p for p, n in c.items() if n >= 3}     # был первым ≥3 раз = стабильно быстрый (случайные не в счёт)
    return fast or {p for p, _ in c.most_common(5)}

def cmd_connect(addr): print(api(f"/v1/peers/{addr}/connect", "POST").get("__err", "ok"))

def cmd_raw():
    import json
    d = api("/v1/peers/connected")
    one = d[0] if isinstance(d, list) and d else d
    print(json.dumps(one, indent=1, ensure_ascii=False))

def _ago(ts):
    import time
    if not ts: return "?"
    s = ts / 1000 if ts > 1e12 else ts        # мс или сек
    d = int(time.time() - s)
    if d < 0 or d > 10**9: return "?"
    return f"{d//60}м{d%60}с назад" if d < 3600 else f"{d//3600}ч{(d%3600)//60}м назад"

def cmd_banned():
    d = api("/v1/peers/all"); peers = d if isinstance(d, list) else []
    b = [p for p in peers if p.get("flags") == "Banned"]
    print(f"забанено: {len(b)}")
    for p in b:
        print(f"  {p.get('addr','?'):24s} забанен: {_ago(p.get('last_banned',0))}  посл.связь: {_ago(p.get('last_connected',0))}  причина: {p.get('ban_reason','?')}")

def cmd_unbanall():
    d = api("/v1/peers/all"); peers = d if isinstance(d, list) else []
    n = 0
    for p in peers:
        if p.get("flags") == "Banned":
            api(f"/v1/peers/{p.get('addr')}/unban", "POST"); n += 1
    print(f"разбанено (дан второй шанс): {n}")

def cmd_watch(n=50, iv=30):
    import time
    fast = learn_fast()
    print(f"AUTO: порог {n}, быстрых защищено {len(fast)} (учу из лога). Ctrl+C стоп", flush=True)
    cyc = 0
    while True:
        if cyc % 10 == 0: fast = learn_fast()            # обновляю список быстрых раз в 10 циклов
        t = tip(); peers = connected(); nb = 0
        for p in peers:
            a = p.get("addr"); lag = t - p.get("height", 0)
            if lag <= n: continue                          # синхронный — не трогаем
            if a in fast and lag <= n * 5: continue        # быстрого щадим при умеренном лаге...
            api(f"/v1/peers/{a}/ban", "POST"); nb += 1     # ...но при СИЛЬНОМ отставании баним даже его
        on = len(fast & {p.get("addr") for p in peers})
        print(f"{time.strftime('%H:%M:%S')} tip={t} подключено={len(peers)} быстрых_на_связи={on} бан={nb}", flush=True)
        cyc += 1; time.sleep(iv)

c = sys.argv[1] if len(sys.argv) > 1 else "list"
if c == "scan": cmd_scan()
elif c == "raw": cmd_raw()
elif c == "banned": cmd_banned()
elif c == "unbanall": cmd_unbanall()
elif c == "connect": cmd_connect(sys.argv[2])
elif c == "watch": cmd_watch(int(sys.argv[2]) if len(sys.argv) > 2 else 5, int(sys.argv[3]) if len(sys.argv) > 3 else 15)
elif c == "list": cmd_list()
elif c == "clean": cmd_clean(int(sys.argv[2]) if len(sys.argv) > 2 else 50)
elif c == "ban": cmd_ban(sys.argv[2])
elif c == "unban": cmd_unban(sys.argv[2])
else: print("команды: list | clean [N] | ban IP:PORT | unban IP:PORT")
