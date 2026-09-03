import urllib.request, base64, urllib.error, os, glob
base = os.path.expanduser("~/.epic/main")
files = [f for f in (base+"/.api_secret", base+"/.foreign_api_secret") if os.path.exists(f)]
files += [f for f in glob.glob(os.path.expanduser("~/.epic/**/.*api_secret"), recursive=True) if f not in files]
URL = "http://127.0.0.1:3413/v1/status"
print("тестирую", URL)
for p in files:
    try: sec = open(p).read().strip()
    except: continue
    name = os.path.basename(p)
    for u in ("epic", "", "grin"):
        a = "Basic " + base64.b64encode((u + ":" + sec).encode()).decode()
        r = urllib.request.Request(URL); r.add_header("Authorization", a)
        try:
            x = urllib.request.urlopen(r, timeout=5); print("%s u=[%s] code=%d  <== РАБОТАЕТ" % (name, u, x.getcode()))
        except urllib.error.HTTPError as e: print("%s u=[%s] code=%d" % (name, u, e.code))
        except Exception as e: print("%s u=[%s] err=%s" % (name, u, e))
