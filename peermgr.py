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

def cmd_watch(n=5, iv=15):
    import time
    print(f"AUTO: баню отставших > {n} блоков каждые {iv}с (Ctrl+C стоп)", flush=True)
    while True:
        t = tip(); peers = connected(); nb = 0
        for p in peers:
            lag = t - p.get("height", 0)
            if lag > n:
                api(f"/v1/peers/{p.get('addr')}/ban", "POST"); nb += 1
        print(f"{time.strftime('%H:%M:%S')} tip={t} подключено={len(peers)} забанено_отставших={nb}", flush=True)
        time.sleep(iv)

c = sys.argv[1] if len(sys.argv) > 1 else "list"
if c == "scan": cmd_scan()
elif c == "watch": cmd_watch(int(sys.argv[2]) if len(sys.argv) > 2 else 5, int(sys.argv[3]) if len(sys.argv) > 3 else 15)
elif c == "list": cmd_list()
elif c == "clean": cmd_clean(int(sys.argv[2]) if len(sys.argv) > 2 else 50)
elif c == "ban": cmd_ban(sys.argv[2])
elif c == "unban": cmd_unban(sys.argv[2])
else: print("команды: list | clean [N] | ban IP:PORT | unban IP:PORT")
