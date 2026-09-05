#!/usr/bin/env python3
# cpuwindow — держит CPU на max ТОЛЬКО вокруг cuckoo-окна, иначе normal.
# Подключается к источнику заданий (нода напрямую ИЛИ прокси) как воркер, читает
# height из job и за LEAD блоков ДО cuckoo (%PERIOD==CUCKOO_MOD) включает HOT,
# после — COLD. Ничего не майнит, только читает.
# Настройки из окружения (cw-start.sh экспортит из config.env):
#   SRC=192.168.1.41:28061     откуда читать задания (нода или прокси)
#   LEAD=1                      за сколько блоков ДО куку греть
#   PERIOD=25  CUCKOO_MOD=4     где cuckoo (height%PERIOD==CUCKOO_MOD)
#   HOT="./cpumode.sh max"      команда «на максимум»
#   COLD="./cpumode.sh normal"  команда «в норму»
import socket, json, os, sys, time, subprocess, signal, shlex

SRC = os.environ.get("SRC", "127.0.0.1:28061")
LEAD = int(os.environ.get("LEAD", "1"))
PERIOD = int(os.environ.get("PERIOD", "25"))
CUCKOO_MOD = int(os.environ.get("CUCKOO_MOD", "4"))
HOT = shlex.split(os.environ.get("HOT", "./cpumode.sh max"))
COLD = shlex.split(os.environ.get("COLD", "./cpumode.sh normal"))
HOST = SRC.split(":")[0]; PORT = int(SRC.split(":")[1]) if ":" in SRC else 28061
state = None

def log(*a): print(time.strftime("%H:%M:%S"), *a, flush=True)
def run(cmd):
    try: subprocess.run(cmd, timeout=30)
    except Exception as e: log("ошибка", cmd, e)

def want_hot(height):
    # d = блоков до ближайшего cuckoo; 0 = на cuckoo. hot если d<=LEAD.
    d = (CUCKOO_MOD - (height % PERIOD)) % PERIOD
    return d <= LEAD

last_h = None
def apply(height):
    global state, last_h
    hot = want_hot(height)
    if height != last_h:                       # пульс: строка на каждый новый блок
        log(f"h={height} %{PERIOD}={height%PERIOD} -> {'ГОРЯЧО(max)' if hot else 'норма'}")
        last_h = height
    if hot and state != "hot":
        log("   ПЕРЕКЛЮЧАЮ -> max"); run(HOT); state = "hot"
    elif not hot and state != "cold":
        log("   ПЕРЕКЛЮЧАЮ -> normal"); run(COLD); state = "cold"

def cleanup(*_):
    log("выход — возвращаю normal"); run(COLD); sys.exit(0)
signal.signal(signal.SIGTERM, cleanup); signal.signal(signal.SIGINT, cleanup)

def session():
    s = socket.create_connection((HOST, PORT), timeout=10); s.settimeout(30)
    try: s.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
    except Exception: pass
    s.sendall(b'{"id":"0","jsonrpc":"2.0","method":"login","params":{"login":"cpuwindow","pass":"","agent":"cpuwindow"}}\n')
    s.sendall(b'{"id":"1","jsonrpc":"2.0","method":"getjobtemplate","params":{"algorithm":"any"}}\n')
    log(f"подключён к {SRC} | LEAD={LEAD} период={PERIOD} cuckoo%={CUCKOO_MOD}")
    buf=b""; last=time.time()
    while True:
        if time.time()-last>20:
            try: s.sendall(b'{"id":"k","jsonrpc":"2.0","method":"keepalive"}\n')
            except Exception: return
            last=time.time()
        try: data=s.recv(8192)
        except socket.timeout: continue
        if not data: return
        buf+=data
        while b"\n" in buf:
            line,buf=buf.split(b"\n",1); line=line.strip()
            if not line: continue
            try: m=json.loads(line)
            except Exception: continue
            p=m.get("params")
            if not isinstance(p,dict) or "height" not in p: p=m.get("result")
            if isinstance(p,dict) and "height" in p:
                try: apply(int(p["height"]))
                except Exception: pass

def main():
    log("cpuwindow старт | SRC", SRC, "| HOT", " ".join(HOT), "| COLD", " ".join(COLD))
    while True:
        try: session()
        except Exception as e: log("нет связи, ретрай 3с:", e)
        time.sleep(3)
main()
