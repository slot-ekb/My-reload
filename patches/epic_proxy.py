#!/usr/bin/env python3
# Прокси: много локальных воркеров -> ОДНА или НЕСКОЛЬКО нод.
# Задания берём с той ноды, где высота СВЕЖЕЕ; каждый submit шлём на ВСЕ ноды (дубль/резерв).
# ВАЖНО: несколько нод имеют смысл только на ОДНОЙ цепи (иначе чужая нода отвергнет шару).
# Запуск: epic_proxy.py "<host1:port1[,host2:port2,...]>" <ЛОКАЛ_ПОРТ> [debug]
import asyncio, json, sys, time, socket

arg = sys.argv[1] if len(sys.argv) > 1 else "127.0.0.1:3416"
NODES = []
for part in arg.split(","):
    part = part.strip()
    if not part: continue
    h = part.split(":")[0]; p = int(part.split(":")[1]) if ":" in part else 3416
    NODES.append((h, p))
LISTEN_PORT = int(sys.argv[2]) if len(sys.argv) > 2 else 3401
DEBUG = len(sys.argv) > 3 and sys.argv[3] == "debug"
HOSTNAME = socket.gethostname()

workers = set()
latest_params = None
latest_height = -1
node_writers = {}     # idx -> writer (только живые)
dbgn = 0
jobs_rx = 0           # заданий принято (суммарно со всех нод)
jobs_tx = 0           # заданий роздано воркерам
sub_rx = 0            # шар получено от воркеров
sub_tx = 0            # отправок шар на ноды (суммарно по всем нодам)
algo_jobs = {}

def nodelay(w):
    try: w.get_extra_info("socket").setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
    except Exception: pass

def log(*a): print(time.strftime("%H:%M:%S"), *a, flush=True)

async def broadcast_job():
    global jobs_tx
    if latest_params is None: return
    msg = (json.dumps({"id": "0", "jsonrpc": "2.0", "method": "job", "params": latest_params}) + "\n").encode()
    for w in list(workers):
        try: w.write(msg); jobs_tx += 1
        except Exception: workers.discard(w)

async def node_link(idx, host, port):
    global latest_params, latest_height, dbgn, jobs_rx
    while True:
        try:
            r, w = await asyncio.open_connection(host, port)
            nodelay(w)
            node_writers[idx] = w
            w.write((json.dumps({"id": "0", "jsonrpc": "2.0", "method": "login",
                                 "params": {"login": HOSTNAME + f"-p{idx}", "pass": "", "agent": "proxy"}}) + "\n").encode())
            w.write((json.dumps({"id": "0", "jsonrpc": "2.0", "method": "getjobtemplate", "params": None}) + "\n").encode())
            await w.drain()
            log(f"нода[{idx}] подключена {host}:{port}")
            async for line in r:
                if DEBUG and dbgn < 5:
                    dbgn += 1; log(f"НОДА[{idx}]>", line.decode(errors='replace').strip()[:200])
                try: msg = json.loads(line)
                except Exception: continue
                p = None
                if msg.get("method") == "job" and isinstance(msg.get("params"), dict): p = msg["params"]
                elif isinstance(msg.get("result"), dict) and "job_id" in msg["result"]: p = msg["result"]
                if p is not None:
                    # задание в майнер берёт АКТИВНАЯ нода = живая с наименьшим индексом.
                    # Пока жива основная[0] — её задание; упала — автоматом со следующей (failover).
                    active = min(node_writers) if node_writers else idx
                    if idx == active:
                        jobs_rx += 1
                        a = p.get("algorithm", "?"); algo_jobs[a] = algo_jobs.get(a, 0) + 1
                        latest_height = p.get("height", 0) or 0; latest_params = p
                        await broadcast_job()
                    # с неактивных нод задания игнорируем — они лишь принимают копии submit
        except Exception as e:
            node_writers.pop(idx, None)
            log(f"нода[{idx}] {host}:{port} отвалилась, реконнект:", e)
            await asyncio.sleep(2)

async def forward_submit(line):
    global sub_tx
    ok = 0
    for w in list(node_writers.values()):
        try: w.write(line); ok += 1
        except Exception: pass
    if ok:
        sub_tx += ok
        for w in list(node_writers.values()):
            try: await w.drain()
            except Exception: pass
    return ok

async def handle_worker(r, w):
    global jobs_tx, sub_rx
    nodelay(w); workers.add(w)
    try:
        if latest_params is not None:
            w.write((json.dumps({"id": "0", "jsonrpc": "2.0", "method": "job", "params": latest_params}) + "\n").encode())
            jobs_tx += 1; await w.drain()
        async for line in r:
            try: msg = json.loads(line)
            except Exception: continue
            m = msg.get("method"); mid = msg.get("id", "0")
            if m == "login":
                w.write((json.dumps({"id": mid, "jsonrpc": "2.0", "method": "login", "result": "ok", "error": None}) + "\n").encode())
                if latest_params is not None:
                    w.write((json.dumps({"id": "0", "jsonrpc": "2.0", "method": "job", "params": latest_params}) + "\n").encode()); jobs_tx += 1
                await w.drain()
            elif m == "getjobtemplate":
                if latest_params is not None:
                    w.write((json.dumps({"id": mid, "jsonrpc": "2.0", "method": "getjobtemplate", "result": latest_params, "error": None}) + "\n").encode()); jobs_tx += 1; await w.drain()
            elif m == "submit":
                sub_rx += 1
                await forward_submit(line)          # на ВСЕ ноды
                w.write((json.dumps({"id": mid, "jsonrpc": "2.0", "method": "submit", "result": "ok", "error": None}) + "\n").encode())
                await w.drain()
            elif m == "status":
                w.write((json.dumps({"id": mid, "jsonrpc": "2.0", "method": "status",
                                     "result": {"id": "0", "height": latest_height if latest_height >= 0 else 0, "difficulty": 1,
                                                "accepted": 0, "rejected": 0, "stale": 0}, "error": None}) + "\n").encode()); await w.drain()
            elif m == "keepalive":
                w.write((json.dumps({"id": mid, "jsonrpc": "2.0", "method": "keepalive", "result": "ok", "error": None}) + "\n").encode()); await w.drain()
    except Exception:
        pass
    finally:
        workers.discard(w)
        try: w.close()
        except Exception: pass

async def stats_loop():
    while True:
        await asyncio.sleep(3)
        brk = " ".join(f"{k}={v}" for k, v in sorted(algo_jobs.items()))
        log(f"СТАТ воркеров={len(workers)} нод_живых={len(node_writers)}/{len(NODES)} высота={latest_height} "
            f"задания_получ={jobs_rx} задания_розд={jobs_tx} шары_получ={sub_rx} шары_отосл={sub_tx} по_алго[{brk}]")

async def keepalive_loop():
    while True:
        await asyncio.sleep(30)
        for w in list(node_writers.values()):
            try:
                w.write((json.dumps({"id": "0", "jsonrpc": "2.0", "method": "keepalive", "params": None}) + "\n").encode())
                await w.drain()
            except Exception: pass

async def main():
    for i, (h, p) in enumerate(NODES):
        asyncio.create_task(node_link(i, h, p))
    asyncio.create_task(stats_loop())
    asyncio.create_task(keepalive_loop())
    srv = await asyncio.start_server(handle_worker, "0.0.0.0", LISTEN_PORT)
    log(f"ПРОКСИ: воркеры -> :{LISTEN_PORT} | ноды -> {', '.join(f'{h}:{p}' for h,p in NODES)}")
    async with srv:
        await srv.serve_forever()

asyncio.run(main())
