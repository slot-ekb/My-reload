#!/usr/bin/env python3
# Минимальный стратум-прокси для Epic.
# Держит ОДНО соединение с нодой, раздаёт задание МНОГИМ воркерам по LAN мгновенно.
# Воркерам отвечает сам (diff=1, ack локально), наверх шлёт их submit'ы.
# Запуск: python3 epic_proxy.py <НОДА_HOST:PORT> <LISTEN_PORT> [debug]
#   пример: python3 epic_proxy.py 212.220.216.27:3416 3400
import asyncio, json, sys, time

arg = sys.argv[1] if len(sys.argv) > 1 else "127.0.0.1:3416"
NODE_HOST = arg.split(":")[0]
NODE_PORT = int(arg.split(":")[1]) if ":" in arg else 3416
LISTEN_PORT = int(sys.argv[2]) if len(sys.argv) > 2 else 3400
DEBUG = len(sys.argv) > 3 and sys.argv[3] == "debug"

workers = set()          # downstream writers
latest_params = None     # последняя JobTemplate (dict)
node_writer = None
dbgn = 0

def log(*a):
    print(time.strftime("%H:%M:%S"), *a, flush=True)

async def broadcast_job():
    if latest_params is None:
        return
    msg = (json.dumps({"id": "0", "jsonrpc": "2.0", "method": "job", "params": latest_params}) + "\n").encode()
    for w in list(workers):
        try:
            w.write(msg)
        except Exception:
            workers.discard(w)

async def node_link():
    global node_writer, latest_params, dbgn
    while True:
        try:
            r, w = await asyncio.open_connection(NODE_HOST, NODE_PORT)
            node_writer = w
            w.write((json.dumps({"id": "0", "jsonrpc": "2.0", "method": "login",
                                 "params": {"login": "", "pass": "", "agent": "epic-proxy"}}) + "\n").encode())
            w.write((json.dumps({"id": "0", "jsonrpc": "2.0", "method": "getjobtemplate", "params": None}) + "\n").encode())
            await w.drain()
            log(f"нода подключена {NODE_HOST}:{NODE_PORT}")
            async for line in r:
                if DEBUG and dbgn < 5:
                    dbgn += 1; log("НОДА>", line.decode(errors='replace').strip()[:300])
                try:
                    msg = json.loads(line)
                except Exception:
                    continue
                p = None
                if msg.get("method") == "job" and isinstance(msg.get("params"), dict):
                    p = msg["params"]
                elif isinstance(msg.get("result"), dict) and "job_id" in msg["result"]:
                    p = msg["result"]
                if p is not None:
                    latest_params = p
                    await broadcast_job()
        except Exception as e:
            node_writer = None
            log("нода отвалилась, реконнект:", e)
            await asyncio.sleep(2)

async def handle_worker(r, w):
    workers.add(w)
    try:
        if latest_params is not None:
            w.write((json.dumps({"id": "0", "jsonrpc": "2.0", "method": "job", "params": latest_params}) + "\n").encode())
            await w.drain()
        async for line in r:
            try:
                msg = json.loads(line)
            except Exception:
                continue
            m = msg.get("method"); mid = msg.get("id", "0")
            if m == "login":
                w.write((json.dumps({"id": mid, "jsonrpc": "2.0", "method": "login", "result": "ok", "error": None}) + "\n").encode())
                if latest_params is not None:
                    w.write((json.dumps({"id": "0", "jsonrpc": "2.0", "method": "job", "params": latest_params}) + "\n").encode())
                await w.drain()
            elif m == "getjobtemplate":
                if latest_params is not None:
                    w.write((json.dumps({"id": mid, "jsonrpc": "2.0", "method": "getjobtemplate", "result": latest_params, "error": None}) + "\n").encode())
                    await w.drain()
            elif m == "submit":
                if node_writer is not None:
                    try:
                        node_writer.write(line); await node_writer.drain()
                    except Exception:
                        pass
                w.write((json.dumps({"id": mid, "jsonrpc": "2.0", "method": "submit", "result": "ok", "error": None}) + "\n").encode())
                await w.drain()
            elif m == "status":
                h = latest_params.get("height", 0) if isinstance(latest_params, dict) else 0
                w.write((json.dumps({"id": mid, "jsonrpc": "2.0", "method": "status",
                                     "result": {"id": "0", "height": h, "difficulty": 1,
                                                "accepted": 0, "rejected": 0, "stale": 0}, "error": None}) + "\n").encode())
                await w.drain()
            elif m == "keepalive":
                w.write((json.dumps({"id": mid, "jsonrpc": "2.0", "method": "keepalive", "result": "ok", "error": None}) + "\n").encode())
                await w.drain()
    except Exception:
        pass
    finally:
        workers.discard(w)
        try: w.close()
        except Exception: pass

async def main():
    asyncio.create_task(node_link())
    srv = await asyncio.start_server(handle_worker, "0.0.0.0", LISTEN_PORT)
    log(f"ПРОКСИ: воркеры -> :{LISTEN_PORT} | нода -> {NODE_HOST}:{NODE_PORT}")
    async with srv:
        await srv.serve_forever()

asyncio.run(main())
