#!/usr/bin/env python3
# nodewatch.py — ставится НА НОДУ. Меряет на часах ноды:
#   TIP  = когда нода узнала новую высоту (опрос API)
#   JOB  = когда нода отдала задание в стратум (слушаем как майнер)
#   DELAY = JOB - TIP  => внутренняя задержка ноды «знаю блок -> отдал работу»
# Сеть тут ~0 (всё локально), поэтому это чистая задержка самой ноды.
#
# Запуск на ноде:
#   python3 nodewatch.py [stratum_host:port] [api_base]
#   по умолчанию: 127.0.0.1:28061  http://127.0.0.1:3413
import socket, json, threading, time, sys, urllib.request

STRATUM = sys.argv[1] if len(sys.argv) > 1 else "127.0.0.1:28061"
API     = sys.argv[2] if len(sys.argv) > 2 else "http://127.0.0.1:3413"
SH, SP  = STRATUM.split(":"); SP = int(SP)

def now(): return time.time()
def ts(t=None):
    t = t if t is not None else now()
    return time.strftime("%H:%M:%S", time.localtime(t)) + f".{int((t%1)*1000):03d}"

tip_seen = {}   # height -> ts когда API впервые показал эту высоту
job_seen = {}   # height -> ts первого джоба этой высоты
cuck_seen = {}  # height -> ts первого cuckoo-джоба
lock = threading.Lock()

def report(h):
    # печатаем строку задержки, когда по высоте известны обе точки
    with lock:
        if h in tip_seen and h in job_seen and not job_seen[h].get("done"):
            t_tip = tip_seen[h]; t_job = job_seen[h]["t"]; algo = job_seen[h]["algo"]
            d = (t_job - t_tip) * 1000
            extra = ""
            if h in cuck_seen:
                dc = (cuck_seen[h] - t_tip) * 1000
                extra = f" | cuckoo-джоб через {dc:+.0f} мс"
            print(f"{ts(t_job)} DELAY h={h}: нода узнала->отдала джоб = {d:+.0f} мс (первый algo={algo}){extra}", flush=True)
            job_seen[h]["done"] = True

def api_poller():
    last = None
    while True:
        try:
            with urllib.request.urlopen(API + "/v1/status", timeout=5) as r:
                st = json.loads(r.read().decode())
            h = st.get("tip", {}).get("height") or st.get("height")
            if h is not None and h != last:
                last = h
                with lock:
                    if h not in tip_seen:
                        tip_seen[h] = now()
                        print(f"{ts()} TIP  нода увидела высоту {h}", flush=True)
                report(h)
        except Exception as e:
            print(f"{ts()} [api] {e}", flush=True); time.sleep(1)
        time.sleep(0.05)   # 50 мс

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
                            last = key
                            t = now()
                            with lock:
                                if h not in job_seen:
                                    job_seen[h] = {"t": t, "algo": algo}
                                if algo == "cuckoo" and h not in cuck_seen:
                                    cuck_seen[h] = t
                            print(f"{ts(t)} JOB  h={h} algo={algo:8s} job_id={jid}", flush=True)
                            report(h)
        except Exception as e:
            print(f"{ts()} [stratum] reconnect: {e}", flush=True); time.sleep(2)

print(f"nodewatch: stratum={STRATUM} api={API}  (Ctrl+C выход)", flush=True)
threading.Thread(target=api_poller, daemon=True).start()
threading.Thread(target=stratum_listener, daemon=True).start()
while True: time.sleep(1)
