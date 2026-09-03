#!/usr/bin/env python3
# nodewatch.py — НА НОДЕ. Ловит удержание блоков и задержку выдачи.
# На каждый новый блок:
#   BLOCK h=... algo=... интервал=<время блока> создан->получен=<разрыв> [метки]
#     создан->получен большой  = блок придержали (создан раньше, вброшен позже)
#     интервал длинный + следом cuckoo = подозрение на удержание под cuckoo
#   JOB   = момент выдачи задания в стратум (клок ноды)
#   DELAY = задержка нода узнала -> отдала джоб
# Запуск: python3 nodewatch.py [stratum_host:port] [api_base]
import socket, json, threading, time, sys, os, glob, base64, urllib.request, urllib.error
from datetime import datetime, timezone

STRATUM = sys.argv[1] if len(sys.argv) > 1 else "127.0.0.1:28061"
API     = sys.argv[2] if len(sys.argv) > 2 else "http://127.0.0.1:3413"
SH, SP  = STRATUM.split(":"); SP = int(SP)

def now(): return time.time()
def ts(t=None):
    t = t if t is not None else now()
    return time.strftime("%H:%M:%S", time.localtime(t)) + f".{int((t%1)*1000):03d}"

# --- секрет: сперва .api_secret (owner путь из конфига — он и работает) ---
def find_secret():
    if os.environ.get("EPIC_API_SECRET"): return os.environ["EPIC_API_SECRET"].strip()
    order = ["~/.epic/main/.api_secret", "/root/.epic/main/.api_secret",
             "~/.epic/main/.foreign_api_secret", "~/.epic/main/.owner_api_secret"]
    for p in order:
        p = os.path.expanduser(p)
        if os.path.isfile(p):
            try:
                s = open(p).read().strip()
                if s: return s
            except: pass
    for g in glob.glob(os.path.expanduser("~/.epic/**/.api_secret"), recursive=True):
        try:
            s = open(g).read().strip()
            if s: return s
        except: pass
    return None

SECRET = find_secret()
AUTH_VARIANTS = []
if SECRET:
    for user in ("epic", "", "grin"):
        AUTH_VARIANTS.append("Basic " + base64.b64encode((user + ":" + SECRET).encode()).decode())
AUTH_VARIANTS.append(None)
AUTH = AUTH_VARIANTS[0]

def api_get(path):
    global AUTH
    last = None
    for a in ([AUTH] + [x for x in AUTH_VARIANTS if x != AUTH]):
        try:
            req = urllib.request.Request(API + path)
            if a: req.add_header("Authorization", a)
            with urllib.request.urlopen(req, timeout=5) as r:
                data = json.loads(r.read().decode())
                if AUTH != a:
                    AUTH = a; print(f"{ts()} [api] авторизация ок", flush=True)
                return data
        except urllib.error.HTTPError as e:
            last = e
            if e.code == 401: continue
            raise
    raise Exception(f"API auth не подошла ({last})")

def parse_ts(s):
    if not s: return None
    try:
        s = s.replace("Z", "+00:00")
        return datetime.fromisoformat(s).timestamp()
    except:
        for fmt in ("%Y-%m-%dT%H:%M:%S%z", "%Y-%m-%dT%H:%M:%S.%f%z", "%Y-%m-%dT%H:%M:%S"):
            try: return datetime.strptime(s, fmt).replace(tzinfo=timezone.utc).timestamp()
            except: pass
    return None

tip_seen = {}; job_seen = {}; cuck_seen = {}; block_info = {}
last_h = None; last_recv = None
lock = threading.Lock()

def report_delay(h):
    with lock:
        if h in tip_seen and h in job_seen and not job_seen[h].get("done"):
            d = (job_seen[h]["t"] - tip_seen[h]) * 1000
            print(f"{ts(job_seen[h]['t'])} DELAY h={h}: узнала->отдала джоб = {d:+.0f} мс", flush=True)
            job_seen[h]["done"] = True

def on_new_height(h, recv):
    global last_h, last_recv
    interval = (recv - last_recv) if last_recv else None
    # алго из стратум-джоба (если уже видели) или из заголовка
    algo = job_seen.get(h, {}).get("algo", "?")
    # заголовок блока -> timestamp создания
    created = None
    try:
        blk = api_get("/v1/blocks/%d" % h)
        hdr = blk.get("header", blk)
        created = parse_ts(hdr.get("timestamp"))
        block_info[h] = {"created": created}
    except Exception as e:
        block_info[h] = {"created": None, "err": str(e)}
    gap = (recv - created) if created else None
    parts = [f"{ts(recv)} BLOCK h={h} algo={algo:8s}"]
    parts.append(f"интервал={interval:5.1f}s" if interval is not None else "интервал=  ?  ")
    parts.append(f"создан->получен={gap:+.1f}s" if gap is not None else "создан->получен=?")
    marks = []
    if interval is not None and interval > 120: marks.append("ДЛИННЫЙ")
    if gap is not None and gap > 5: marks.append("!!ПРИДЕРЖАН?")
    # если предыдущий был длинный, а этот cuckoo — подсветить
    if algo == "cuckoo" and last_h in block_info:
        pass
    if marks: parts.append(" ".join(marks))
    print("  ".join(parts), flush=True)
    last_h = h; last_recv = recv

def api_poller():
    global last_h
    print(f"{ts()} [api] секрет: {'найден' if SECRET else 'НЕ найден'}", flush=True)
    last = None; warned = False
    while True:
        try:
            st = api_get("/v1/status")
            h = st.get("tip", {}).get("height") or st.get("height")
            if h is not None and h != last:
                last = h; recv = now()
                with lock:
                    if h not in tip_seen: tip_seen[h] = recv
                on_new_height(h, recv)
                report_delay(h)
                warned = False
        except Exception as e:
            if not warned:
                print(f"{ts()} [api] {e}", flush=True); warned = True
            time.sleep(1)
        time.sleep(0.05)

def stratum_listener():
    while True:
        try:
            s = socket.create_connection((SH, SP), timeout=10); s.settimeout(90)
            try: s.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
            except: pass
            s.sendall(b'{"id":"0","jsonrpc":"2.0","method":"login","params":{"login":"nodewatch","pass":"","agent":"nodewatch"}}\n')
            s.sendall(b'{"id":"1","jsonrpc":"2.0","method":"getjobtemplate","params":null}\n')
            print(f"{ts()} [stratum] подключён к {SH}:{SP}", flush=True)
            buf = b""; last = None; ka = now()
            while True:
                if now() - ka > 20:
                    try: s.sendall(b'{"id":"k","jsonrpc":"2.0","method":"keepalive"}\n')
                    except: break
                    ka = now()
                try: d = s.recv(8192)
                except socket.timeout: continue
                if not d: break
                buf += d
                while b"\n" in buf:
                    line, buf = buf.split(b"\n", 1)
                    if not line.strip(): continue
                    try: m = json.loads(line)
                    except: continue
                    p = m.get("params") if isinstance(m.get("params"), dict) else m.get("result")
                    if isinstance(p, dict) and "algorithm" in p:
                        h = p.get("height"); algo = p.get("algorithm"); jid = p.get("job_id")
                        key = (h, jid, algo)
                        if key != last:
                            last = key; t = now()
                            with lock:
                                if h not in job_seen: job_seen[h] = {"t": t, "algo": algo}
                                if algo == "cuckoo" and h not in cuck_seen: cuck_seen[h] = t
                            print(f"{ts(t)} JOB   h={h} algo={algo:8s} job_id={jid}", flush=True)
                            report_delay(h)
        except Exception as e:
            print(f"{ts()} [stratum] reconnect: {e}", flush=True); time.sleep(2)

print(f"nodewatch: stratum={STRATUM} api={API}", flush=True)
threading.Thread(target=api_poller, daemon=True).start()
threading.Thread(target=stratum_listener, daemon=True).start()
while True: time.sleep(1)
