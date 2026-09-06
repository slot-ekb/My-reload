#!/usr/bin/env python3
# Фейк-нода diffscan: для КАЖДОЙ полученной шары считает её ВЕС из pow (blake2b) и ведёт
# гистограмму «сколько шар тяжелее порога». Майнер вес не присылает (шлёт только nonce+pow),
# поэтому считаем сами. Абсолют не равен реальному ноду epic, но РАСПРЕДЕЛЕНИЕ веса верное
# (хэш случайного решения равномерен -> P(вес>=D) ~ 1/D). Годится сравнивать раскладки.
#   env DIFF=1   — share difficulty в задании (1 = майнер шлёт все найденные шары)
#   env LOGW=on  — печатать вес каждой шары (иначе только гистограмма раз в 5с)
import socket, threading, json, sys, time, os, hashlib
PORT = int(sys.argv[1]) if len(sys.argv)>1 else 3799
DIFF = int(os.environ.get("DIFF","1") or 1)
LOGW = os.environ.get("LOGW","off") == "on"
PREPOW = "000600000000003844ec000000006a940165c3019a2165defebbd26e62b720b2371530caa28e1f5bdd26a00d7174420b2a4eca624c18f22463568acf497a8b0b43e2198ec449c606724905b7c1a8bd95d1512cc690981eb4c3ca3b12ec35751228da325dd6a07359ceebeb6acbd13738727066b4dc98d361c28edbd1a9f2b7db287205ccc19a037842451cde0ab71cfed988ab354f3ab87e8dde794ab96fa6b5a4dd94e29b8e63986a47b35e1f0cfd55491008b48f8b39702630bc392471552855bac84a4e7ed2f4075d3038fc0414da854700000000008d455800000000007aee23000000000000000400000000000115f9710100006d51b3b5849202001031907610c9090370566c89d8fbed070000000d"
EPOCH = [14,16,161,199,1,78,223,82,219,196,225,96,45,50,129,175,152,103,144,127,35,59,23,31,159,139,114,147,9,48,28,27]
HEIGHT = 1000000
BUCKETS = [1,2,5,10,50,100,1000,10000,100000]
hist = {b:0 for b in BUCKETS}
total = 0; wmax = 0.0; wsum = 0.0
lock = threading.Lock()
MAXH = float(1 << 256)

def job_params():
    return {"height":HEIGHT,"job_id":0,
            "difficulty":[["cuckoo",DIFF],["randomx",4000],["progpow",1000000000]],
            "block_difficulty":[["cuckoo",1],["randomx",1],["progpow",1]],
            "pre_pow":PREPOW,"epochs":[[3687060,3688060,EPOCH]],"algorithm":"cuckoo"}
def send(sock,obj):
    try: sock.sendall((json.dumps(obj)+"\n").encode())
    except: pass
def job_notif(): return {"id":"0","jsonrpc":"2.0","method":"job","params":job_params()}

def weight(powl):
    # вес = 2^256 / blake2b(pow). Детерминирован по решению, распределение как у сложности.
    try:
        b = b"".join(int(x).to_bytes(8,"little",signed=False) for x in powl)
    except Exception:
        return None
    hi = int.from_bytes(hashlib.blake2b(b, digest_size=32).digest(), "big")
    return (MAXH / hi) if hi else None

def handle(conn,addr):
    global total, wmax, wsum
    send(conn, job_notif())
    def pusher():
        while True:
            time.sleep(5); send(conn, job_notif())
    threading.Thread(target=pusher,daemon=True).start()
    buf=b""
    while True:
        try: data=conn.recv(4096)
        except: break
        if not data: break
        buf+=data
        while b"\n" in buf:
            line,buf=buf.split(b"\n",1)
            if not line.strip(): continue
            try: msg=json.loads(line)
            except: continue
            m=msg.get("method",""); mid=msg.get("id","0")
            if m=="login":
                send(conn,{"id":mid,"jsonrpc":"2.0","method":"login","result":"ok","error":None}); send(conn, job_notif())
            elif m=="getjobtemplate":
                send(conn,{"id":mid,"jsonrpc":"2.0","method":"getjobtemplate","result":job_params(),"error":None})
            elif m=="submit":
                pp=msg.get("params",{}) or {}
                w=weight(pp.get("pow"))
                with lock:
                    total+=1
                    if w is not None:
                        wsum+=w
                        if w>wmax: wmax=w
                        for b in BUCKETS:
                            if w>=b: hist[b]+=1
                    n=total
                if LOGW and w is not None:
                    print(f"шара #{n} вес={w:.2f}", flush=True)
                send(conn,{"id":mid,"jsonrpc":"2.0","method":"submit","result":"ok","error":None})
            else:
                send(conn,{"id":mid,"jsonrpc":"2.0","method":m,"result":"ok","error":None})
    conn.close()

def stats():
    while True:
        time.sleep(5)
        with lock:
            t=total; wm=wmax; avg=(wsum/t) if t else 0; h=dict(hist)
        brk=" ".join(f">={b}={h[b]}" for b in BUCKETS)
        print(f"ВЕС-ГИСТОГРАММА: шар={t} ср={avg:.2f} макс={wm:.2f} | {brk}", flush=True)
threading.Thread(target=stats,daemon=True).start()

s=socket.socket(socket.AF_INET,socket.SOCK_STREAM); s.setsockopt(socket.SOL_SOCKET,socket.SO_REUSEADDR,1)
s.bind(("0.0.0.0",PORT)); s.listen(64)
print(f"diffscan фейк-нода на :{PORT} | DIFF={DIFF} LOGW={LOGW}", flush=True)
while True:
    c,a=s.accept(); threading.Thread(target=handle,args=(c,a),daemon=True).start()
