#!/usr/bin/env python3
"""Perch bridge command daemon - whitelisted remote window ops.

Verbs (GET, one call): raise-app, minimize-app, open-url, tile-pair, display, frontmost, fullscreen-app, open-file.
Auth: 128-bit token in the URL path (/<token>/<verb>?args). 404 on bad token.
Binds 127.0.0.1 only; exposure is via tailscale serve/funnel. No shell, no
arbitrary AppleScript - fixed templates, args passed via osascript argv.

Runs as a tmux window in the agent session, same convention as bridge-writer:
    tmux new-window -t agent -n cmd-server 'python3 ~/Desktop/Playground/perch/Scripts/cmd-server.py'
Kill: tmux kill-window -t agent:cmd-server  (and `tailscale serve --https=8444 off` to unexpose)
"""
import json, os, re, subprocess, time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs

PORT = 8788
TOKEN_PATH = os.path.expanduser("~/.perch-bridge/cmd.token")
LOG = os.path.expanduser("~/.perch-bridge/cmd.log")
SCREEN_W, TOP, H = 1512, 33, 916  # his display: 1512x982pt, menubar 33
HALF = SCREEN_W // 2

TOKEN = open(TOKEN_PATH).read().strip()
APP_RE = re.compile(r"^[A-Za-z0-9 ._\-()]{1,64}$")
URL_RE = re.compile(r"^https?://[^\s'\"\\]{4,300}$")

def log(msg):
    with open(LOG, "a") as f:
        f.write(f"{time.strftime('%Y-%m-%d %H:%M:%S')} {msg}\n")

def run(cmd, timeout=8):
    r = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
    return r.returncode, (r.stdout or "").strip(), (r.stderr or "").strip()

def osa(script, *args):
    return run(["osascript", "-e", "on run argv", "-e", script, "-e", "end run", *args])

def valid_app(name):
    if not name or not APP_RE.match(name):
        return None
    rc, out, _ = run(["osascript", "-e", f'id of app "{name}"'])
    return name if rc == 0 else None

def frontmost():
    rc, out, _ = osa('tell application "System Events" to return name of first process whose frontmost is true')
    return out

def ax_geo(app):
    rc, out, _ = osa(
        'tell application "System Events" to tell process (item 1 of argv)\n'
        'set p to position of window 1\nset s to size of window 1\n'
        'return (item 1 of p as text) & "," & (item 2 of p) & "," & (item 1 of s) & "," & (item 2 of s)', app)
    return out if rc == 0 else None

def v_raise(q):
    app = valid_app((q.get("app") or [""])[0])
    if not app: return {"ok": False, "err": "bad app"}
    run(["open", "-a", app])
    time.sleep(0.4)
    return {"ok": True, "frontmost": frontmost()}

def v_minimize(q):
    app = valid_app((q.get("app") or [""])[0])
    if not app: return {"ok": False, "err": "bad app"}
    rc, _, err = osa(
        'tell application "System Events"\ntell process (item 1 of argv)\n'
        'repeat with w in windows\ntry\nset value of attribute "AXMinimized" of w to true\nend try\nend repeat\n'
        'end tell\nend tell', app)
    return {"ok": rc == 0, "err": err if rc else None}

def v_open_url(q):
    url = (q.get("url") or [""])[0]
    app = valid_app((q.get("app") or [""])[0]) if q.get("app") else None
    if not URL_RE.match(url): return {"ok": False, "err": "bad url"}
    if q.get("app") and not app: return {"ok": False, "err": "bad app"}
    if (q.get("dry") or [""])[0] == "1":
        return {"ok": True, "dry": True, "url": url, "app": app}
    cmd = ["open", "-a", app, url] if app else ["open", url]
    rc, _, err = run(cmd)
    return {"ok": rc == 0, "err": err if rc else None}

def v_tile(q):
    left = valid_app((q.get("left") or [""])[0])
    right = valid_app((q.get("right") or [""])[0])
    if not left or not right: return {"ok": False, "err": "bad app(s)"}
    url = (q.get("url") or [""])[0]
    pl = (q.get("playlist") or [""])[0]
    dry = (q.get("dry") or [""])[0] == "1"
    if url and not URL_RE.match(url): return {"ok": False, "err": "bad url"}
    lg, rg = ax_geo(left), ax_geo(right)
    done = (lg == f"0,{TOP},{HALF},{H}" and rg == f"{HALF},{TOP},{HALF},{H}")
    if done: return {"ok": True, "state": "ALREADY-DONE", "left": lg, "right": rg}
    if dry: return {"ok": True, "state": "WOULD-APPLY", "left": lg, "right": rg}
    run(["open", "-a", left]); time.sleep(1.2)
    if url and right == "Google Chrome":
        osa('tell application "Google Chrome" to if (count of windows) is 0 then make new window')
        rc, cur, _ = osa('tell application "Google Chrome" to get URL of active tab of front window')
        if cur != url:
            osa('tell application "Google Chrome" to set URL of active tab of front window to (item 1 of argv)', url)
    if pl and left == "Music" and APP_RE.match(pl):
        osa('tell application "Music" to reveal user playlist (item 1 of argv)', pl)
    run(["open", "-a", right]); time.sleep(0.5)
    osa('tell application "System Events"\n'
        'tell process (item 1 of argv)\nset position of window 1 to {0, 33}\nset size of window 1 to {756, 916}\nend tell\n'
        'tell process (item 2 of argv)\nset position of window 1 to {756, 33}\nset size of window 1 to {756, 916}\nend tell\n'
        'end tell', left, right)
    return {"ok": True, "state": "APPLIED", "left": ax_geo(left), "right": ax_geo(right)}

def v_display(q):
    text = (q.get("text") or [""])[0]
    if not text or len(text) > 200 or any(c in text for c in "\n\r"):
        return {"ok": False, "err": "bad text (1-200 chars, one line)"}
    secs = (q.get("secs") or ["20"])[0]
    if not re.match(r"^[0-9]{1,3}$", secs): secs = "20"
    subprocess.Popen(["swift", os.path.expanduser("~/.instinct/bin/showtext.swift"), text, secs],
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return {"ok": True, "text": text, "secs": int(secs)}

def v_frontmost(q):
    return {"ok": True, "frontmost": frontmost()}

def v_fullscreen(q):
    app = valid_app((q.get("app") or [""])[0])
    if not app: return {"ok": False, "err": "bad app"}
    rc, _, err = osa(
        'tell application "System Events"\ntell process (item 1 of argv)\n'
        'set value of attribute "AXFullScreen" of window 1 to true\nend tell\nend tell', app)
    if rc == 0: return {"ok": True, "app": app, "via": "ax"}
    rc2, _, err2 = osa(
        'tell application "System Events"\ntell process (item 1 of argv)\n'
        'click menu item "Toggle Full Screen" of menu 1 of menu bar item "View" of menu bar 1\n'
        'end tell\nend tell', app)
    if rc2 == 0: return {"ok": True, "app": app, "via": "menu"}
    rc3, _, err3 = osa(
        'tell application "System Events"\ntell process (item 1 of argv)\n'
        'click menu item "Enter Full Screen" of menu 1 of menu bar item "View" of menu bar 1\n'
        'end tell\nend tell', app)
    return {"ok": rc3 == 0, "app": app, "via": "menu2" if rc3 == 0 else None,
            "err": (err or "")[:120] + " | " + (err2 or "")[:120] + " | " + (err3 or "")[:120] if rc3 else None}

HOME_PREFIX = os.path.realpath(os.path.expanduser("~")) + "/"
def v_open_file(q):
    p = (q.get("path") or [""])[0]
    if not p or "\x00" in p: return {"ok": False, "err": "bad path"}
    rp = os.path.realpath(os.path.expanduser(p))
    if not rp.startswith(HOME_PREFIX): return {"ok": False, "err": "path outside home"}
    if not os.path.exists(rp): return {"ok": False, "err": "not found"}
    rc, _, err = run(["open", rp])
    return {"ok": rc == 0, "err": err if rc else None}

VERBS = {"raise-app": v_raise, "minimize-app": v_minimize, "open-url": v_open_url, "tile-pair": v_tile, "display": v_display,
         "frontmost": v_frontmost, "fullscreen-app": v_fullscreen, "open-file": v_open_file}

class H(BaseHTTPRequestHandler):
    def do_GET(self):
        parts = [p for p in urlparse(self.path).path.split("/") if p]
        if len(parts) != 2 or parts[0] != TOKEN or parts[1] not in VERBS:
            self.send_response(404); self.end_headers(); return
        verb = parts[1]
        q = parse_qs(urlparse(self.path).query)
        try:
            res = VERBS[verb](q)
        except Exception as e:
            res = {"ok": False, "err": str(e)[:200]}
        log(f"{self.client_address[0]} {verb} {json.dumps({k: v[0] for k, v in q.items()})} -> {json.dumps(res)[:200]}")
        body = json.dumps(res).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)
    def log_message(self, *a):  # silence default stderr access log
        pass

if __name__ == "__main__":
    ThreadingHTTPServer(("127.0.0.1", PORT), H).serve_forever()
