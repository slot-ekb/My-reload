#!/usr/bin/env python3
# Фейк-стратум: непрерывно отдаёт epic-miner cuckatoo-джоб (без пауз), для нагрузочного теста.
# Usage: python3 fakestratum.py [порт]
import socket, threading, json, sys, time, os
PORT = int(sys.argv[1]) if len(sys.argv)>1 else 3499
ROTATE = int(os.environ.get("ROTATE_JOB","0") or 0)   # сек между сменами блока (0=не менять)
conns = set(); conns_lock = threading.Lock()
subs_total = 0            # всего submit долетело до ноды
acc_total = 0; stale_total = 0; rej_total = 0
seen = set()              # (job_id,nonce) для отлова дублей
subs_lock = threading.Lock()
CUR_JOB_ID = 0
PREPOW = "000600000000003844ec000000006a940165c3019a2165defebbd26e62b720b2371530caa28e1f5bdd26a00d7174420b2a4eca624c18f22463568acf497a8b0b43e2198ec449c606724905b7c1a8bd95d1512cc690981eb4c3ca3b12ec35751228da325dd6a07359ceebeb6acbd13738727066b4dc98d361c28edbd1a9f2b7db287205ccc19a037842451cde0ab71cfed988ab354f3ab87e8dde794ab96fa6b5a4dd94e29b8e63986a47b35e1f0cfd55491008b48f8b39702630bc392471552855bac84a4e7ed2f4075d3038fc0414da854700000000008d455800000000007aee23000000000000000400000000000115f9710100006d51b3b5849202001031907610c9090370566c89d8fbed070000000d" or "00"*118
EPOCH = [14,16,161,199,1,78,223,82,219,196,225,96,45,50,129,175,152,103,144,127,35,59,23,31,159,139,114,147,9,48,28,27]
HEIGHT = 1000000   # постоянная высота -> майнер не сбрасывает работу
def job_params():
    return {"height":HEIGHT,"job_id":CUR_JOB_ID,
            "difficulty":[["cuckoo",1],["randomx",4000],["progpow",1000000000]],
            "block_difficulty":[["cuckoo",1],["randomx",1],["progpow",1]],
            "pre_pow":PREPOW,"epochs":[[3687060,3688060,EPOCH]],"algorithm":"cuckoo"}
def send(sock,obj):
    try: sock.sendall((json.dumps(obj)+"\n").encode())
    except: pass
def job_notif():
    return {"id":"0","jsonrpc":"2.0","method":"job","params":job_params()}
def handle(conn,addr):
    subs=0
    with conns_lock: conns.add(conn)
    send(conn, job_notif())  # сразу дать работу
    def pusher():
        while True:
            time.sleep(5); send(conn, job_notif())  # держим живым
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
                send(conn,{"id":mid,"jsonrpc":"2.0","method":"login","result":"ok","error":None})
                send(conn, job_notif())
            elif m=="getjobtemplate":
                send(conn,{"id":mid,"jsonrpc":"2.0","method":"getjobtemplate","result":job_params(),"error":None})
            elif m=="submit":
                global subs_total, acc_total, stale_total, rej_total
                pp=msg.get("params",{}) or {}
                nonce=pp.get("nonce"); h=pp.get("height"); jid=pp.get("job_id",0)
                with subs_lock:
                    subs_total += 1; key=(h,jid,nonce)
                    if nonce is None or not pp.get("pow"):
                        rej_total+=1; verdict="reject"; why="bad"
                    elif key in seen:
                        rej_total+=1; verdict="reject"; why="dup"
                    elif h is not None and h!=HEIGHT:
                        stale_total+=1; verdict="stale"; why="old_height"; seen.add(key)
                    elif jid!=CUR_JOB_ID:
                        stale_total+=1; verdict="stale"; why="old_job"; seen.add(key)
                    else:
                        acc_total+=1; verdict="accept"; why=""; seen.add(key)
                    n=subs_total
                if verdict=="accept":
                    send(conn,{"id":mid,"jsonrpc":"2.0","method":"submit","result":"ok","error":None})
                else:
                    send(conn,{"id":mid,"jsonrpc":"2.0","method":"submit","result":None,"error":{"code":-1,"message":verdict+(":"+why if why else "")}})
                print(f"НОДА<- #{n} {verdict}{('/'+why) if why else ''} nonce={nonce} h={h} job={jid}", flush=True)
            elif m in ("keepalive","status"):
                send(conn,{"id":mid,"jsonrpc":"2.0","method":m,"result":"ok","error":None})
            else:
                send(conn,{"id":mid,"jsonrpc":"2.0","method":m,"result":"ok","error":None})
    with conns_lock: conns.discard(conn)
    conn.close()
def stats():
    last=0
    while True:
        time.sleep(5)
        with subs_lock: t,a,s,r=subs_total,acc_total,stale_total,rej_total
        print(f"НОДА СТАТ: шары_на_ноде={t} accept={a} stale={s} reject={r} (+{t-last} за 5с)", flush=True); last=t
threading.Thread(target=stats,daemon=True).start()
def rotator():
    global HEIGHT, CUR_JOB_ID
    while True:
        time.sleep(ROTATE)
        with subs_lock: HEIGHT += 1; CUR_JOB_ID += 1
        j = job_notif()
        with conns_lock:
            for c in list(conns):
                try: send(c, j)
                except: conns.discard(c)
        print(f"НОДА: новый блок height={HEIGHT} job_id={CUR_JOB_ID} (ротация {ROTATE}с)", flush=True)
if ROTATE > 0:
    threading.Thread(target=rotator,daemon=True).start()
    print(f"РОТАЦИЯ ВКЛ: блок меняется каждые {ROTATE}с -> будут stale", flush=True)
s=socket.socket(socket.AF_INET,socket.SOCK_STREAM); s.setsockopt(socket.SOL_SOCKET,socket.SO_REUSEADDR,1)
s.bind(("0.0.0.0",PORT)); s.listen(64)
print(f"фейк-стратум на :{PORT}, cuckatoo job непрерывно (pre_pow len={len(PREPOW)})")
while True:
    c,a=s.accept(); threading.Thread(target=handle,args=(c,a),daemon=True).start()
