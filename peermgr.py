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

# быстрые хабы (первые на cuckoo/pre-cuckoo) — НЕ банить, держать
KEEP = {"3.133.157.114:3414", "212.95.62.131:3434", "57.128.208.109:3414",
        "89.58.53.79:3414", "178.156.236.136:3414", "37.27.182.223:3414",
        "73.97.43.138:3414", "91.82.65.18:3414", "66.29.156.83:3434",
        "195.162.57.26:3414", "161.97.160.59:3414"}

def cmd_connect(addr): print(api(f"/v1/peers/{addr}/connect", "POST").get("__err", "ok"))

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

def cmd_watch(n=5, iv=15):
    import time
    print(f"AUTO: баню отставших >{n}, держу {len(KEEP)} быстрых хабов. Ctrl+C стоп", flush=True)
    while True:
        t = tip(); peers = connected()
        conn = {p.get("addr") for p in peers}; nb = 0
        for p in peers:
            a = p.get("addr")
            if a in KEEP: continue                       # хабы не трогаем
            if t - p.get("height", 0) > n:
                api(f"/v1/peers/{a}/ban", "POST"); nb += 1
        rc = 0                                            # подтянуть отсутствующие хабы
        for hub in KEEP:
            if hub not in conn:
                if not api(f"/v1/peers/{hub}/connect", "POST").get("__err"): rc += 1
        hubs_on = len(KEEP & conn)
        print(f"{time.strftime('%H:%M:%S')} tip={t} подключено={len(peers)} хабов_онлайн={hubs_on} бан={nb} подтянул={rc}", flush=True)
        time.sleep(iv)

c = sys.argv[1] if len(sys.argv) > 1 else "list"
if c == "scan": cmd_scan()
elif c == "banned": cmd_banned()
elif c == "unbanall": cmd_unbanall()
elif c == "connect": cmd_connect(sys.argv[2])
elif c == "watch": cmd_watch(int(sys.argv[2]) if len(sys.argv) > 2 else 5, int(sys.argv[3]) if len(sys.argv) > 3 else 15)
elif c == "list": cmd_list()
elif c == "clean": cmd_clean(int(sys.argv[2]) if len(sys.argv) > 2 else 50)
elif c == "ban": cmd_ban(sys.argv[2])
elif c == "unban": cmd_unban(sys.argv[2])
else: print("команды: list | clean [N] | ban IP:PORT | unban IP:PORT")
