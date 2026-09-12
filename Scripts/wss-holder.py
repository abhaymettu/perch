#!/usr/bin/env python3
"""wss-holder.py -- resident WSS holder for the Jarvis fast lane.

Holds one WebSocket to the Mac's instinct-daemon (docs/instinct-daemon-spec.md,
WS /v1/ctl) and exposes it to other cloud-side scripts over a loopback unix
socket. Python 3 stdlib only (targets 3.9: no match, no X | Y unions). See
docs/fastlane/SPEC.md FR-A and docs/fastlane/PLAN.md decisions 1-4.

Restart recipe:

    nohup python3 Scripts/wss-holder.py serve >> ~/.perch-bridge/holder/nohup.out 2>&1 &
    python3 Scripts/wss-holder.py status
    python3 Scripts/wss-holder.py stop   (or kill the pid)

Config (env, all optional):

    HOLDER_URL              wss://abhays-macbook-pro.tail4948a2.ts.net:10000/v1/ctl
    HOLDER_DIR              ~/.perch-bridge/holder
    HOLDER_TOKEN_FILE       ~/.perch-bridge/device.token
    HOLDER_TOKEN_CMD        unset; if set, run at start to (re)write the token file
    HOLDER_SHELL_TOKEN_FILE ~/.perch-bridge/shell.token (optional)
    HOLDER_SESSION          holder-<hostname>-<pid>

Never logs or prints the token. The log() function refuses to write a line
containing the live token value.
"""

import base64
import hashlib
import json
import os
import random
import re
import socket
import socketserver
import ssl
import struct
import subprocess
import sys
import threading
import time
import uuid
from urllib.parse import urlsplit

GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"

# ---------------------------------------------------------------------------
# config
# ---------------------------------------------------------------------------


def _expand(p):
    return os.path.expanduser(os.path.expandvars(p))


HOLDER_URL = os.environ.get(
    "HOLDER_URL", "wss://abhays-macbook-pro.tail4948a2.ts.net:10000/v1/ctl"
)
HOLDER_DIR = _expand(os.environ.get("HOLDER_DIR", "~/.perch-bridge/holder"))
HOLDER_TOKEN_FILE = _expand(
    os.environ.get("HOLDER_TOKEN_FILE", "~/.perch-bridge/device.token")
)
HOLDER_TOKEN_CMD = os.environ.get("HOLDER_TOKEN_CMD")
# Optional: TCP-connect to this address instead of the URL hostname (SNI and Host stay
# the hostname). On the Mac itself the funnel hostname resolves to the tailnet IP and
# tailscaled short-circuits it; pinning a public ingress IP forces the relayed path
# the cloud actually takes. Leave unset on the cloud.
HOLDER_CONNECT_HOST = os.environ.get("HOLDER_CONNECT_HOST")
HOLDER_SHELL_TOKEN_FILE = _expand(
    os.environ.get("HOLDER_SHELL_TOKEN_FILE", "~/.perch-bridge/shell.token")
)
HOLDER_SESSION = os.environ.get(
    "HOLDER_SESSION", "holder-%s-%d" % (socket.gethostname(), os.getpid())
)

SOCK_PATH = os.path.join(HOLDER_DIR, "holder.sock")
STATE_PATH = os.path.join(HOLDER_DIR, "state.json")
LOG_PATH = os.path.join(HOLDER_DIR, "holder.log")
SPOOL_DIR = os.path.join(HOLDER_DIR, "spool")
SPOOL_DONE_DIR = os.path.join(SPOOL_DIR, "done")

PING_INTERVAL_S = 20
DEAD_AFTER_S = 40
BACKOFF_STEPS = [1, 2, 4, 8, 16, 30]
CONNECT_TIMEOUT_S = 5
REPLAY_TIMEOUT_S = 15
ORCH_ACTIONS = ("run", "say", "classify")

# ---------------------------------------------------------------------------
# logging (never the token)
# ---------------------------------------------------------------------------

_log_lock = threading.Lock()
_token_value = None  # set once loaded, guarded against in log()


def _set_token_for_guard(tok):
    global _token_value
    _token_value = tok


def log(msg):
    if _token_value and _token_value in msg:
        raise AssertionError("refusing to log a line containing the token")
    line = "%s %s" % (time.strftime("%Y-%m-%d %H:%M:%S", time.localtime()), msg)
    with _log_lock:
        sys.stderr.write(line + "\n")
        sys.stderr.flush()
        try:
            with open(LOG_PATH, "a") as f:
                f.write(line + "\n")
        except OSError:
            pass


# ---------------------------------------------------------------------------
# token handling
# ---------------------------------------------------------------------------


def load_token():
    """Fetch (or reuse) the device token. Never returns it via print/log."""
    if HOLDER_TOKEN_CMD:
        try:
            out = subprocess.run(
                HOLDER_TOKEN_CMD,
                shell=True,
                capture_output=True,
                timeout=30,
            )
            if out.returncode == 0:
                tok = out.stdout.decode("utf-8", "replace").strip()
                if tok:
                    parent = os.path.dirname(HOLDER_TOKEN_FILE)
                    if parent and not os.path.isdir(parent):
                        os.makedirs(parent, mode=0o700, exist_ok=True)
                    fd = os.open(
                        HOLDER_TOKEN_FILE, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600
                    )
                    with os.fdopen(fd, "w") as f:
                        f.write(tok)
                    os.chmod(HOLDER_TOKEN_FILE, 0o600)
                    return tok
        except (OSError, subprocess.SubprocessError):
            pass
        if os.path.isfile(HOLDER_TOKEN_FILE):
            log("token: reused existing file")
            with open(HOLDER_TOKEN_FILE) as f:
                return f.read().strip()
        sys.stderr.write(
            "wss-holder: HOLDER_TOKEN_CMD failed and no token file at %s\n"
            % HOLDER_TOKEN_FILE
        )
        sys.exit(3)
    if os.path.isfile(HOLDER_TOKEN_FILE):
        with open(HOLDER_TOKEN_FILE) as f:
            return f.read().strip()
    sys.stderr.write(
        "wss-holder: no HOLDER_TOKEN_CMD set and no token file at %s\n"
        % HOLDER_TOKEN_FILE
    )
    sys.exit(3)


def load_shell_token():
    if os.path.isfile(HOLDER_SHELL_TOKEN_FILE):
        with open(HOLDER_SHELL_TOKEN_FILE) as f:
            tok = f.read().strip()
            return tok or None
    return None


# ---------------------------------------------------------------------------
# RFC 6455 websocket client (text frames, masked client->server)
# ---------------------------------------------------------------------------


class WSClosed(Exception):
    pass


class WSClient(object):
    """Minimal hand-rolled RFC 6455 client over ssl+socket. Text frames only
    on the send side; on receive handles text(1)/close(8)/ping(9)/pong(10)
    and reassembles continuation (0) fragments."""

    def __init__(self, url, connect_timeout=CONNECT_TIMEOUT_S):
        self.url = url
        self.connect_timeout = connect_timeout
        self.sock = None
        self._send_lock = threading.Lock()

    def connect(self):
        parts = urlsplit(self.url)
        if parts.scheme not in ("ws", "wss"):
            raise ValueError("unsupported scheme: %s" % parts.scheme)
        host = parts.hostname
        port = parts.port or (443 if parts.scheme == "wss" else 80)
        path = parts.path or "/"
        if parts.query:
            path += "?" + parts.query

        raw = socket.create_connection((HOLDER_CONNECT_HOST or host, port),
                                       timeout=self.connect_timeout)
        if parts.scheme == "wss":
            ctx = ssl.create_default_context()
            sock = ctx.wrap_socket(raw, server_hostname=host)
        else:
            sock = raw
        sock.settimeout(self.connect_timeout)

        key = base64.b64encode(os.urandom(16)).decode("ascii")
        req = (
            "GET %s HTTP/1.1\r\n"
            "Host: %s\r\n"
            "Upgrade: websocket\r\n"
            "Connection: Upgrade\r\n"
            "Sec-WebSocket-Key: %s\r\n"
            "Sec-WebSocket-Version: 13\r\n"
            "\r\n" % (path, host, key)
        )
        sock.sendall(req.encode("ascii"))

        resp = b""
        while b"\r\n\r\n" not in resp:
            chunk = sock.recv(4096)
            if not chunk:
                raise WSClosed("connection closed during handshake")
            resp += chunk
            if len(resp) > 65536:
                raise WSClosed("handshake response too large")
        head, _, rest = resp.partition(b"\r\n\r\n")
        lines = head.decode("iso-8859-1").split("\r\n")
        status_line = lines[0]
        if " 101 " not in (" " + status_line + " "):
            raise WSClosed("bad handshake status: %s" % status_line)
        headers = {}
        for line in lines[1:]:
            if ":" in line:
                k, v = line.split(":", 1)
                headers[k.strip().lower()] = v.strip()
        accept = headers.get("sec-websocket-accept")
        expected = base64.b64encode(
            hashlib.sha1((key + GUID).encode("ascii")).digest()
        ).decode("ascii")
        if accept != expected:
            raise WSClosed("bad Sec-WebSocket-Accept")

        sock.settimeout(None)
        self.sock = sock
        self._recv_buf = rest

    def _recv_exact(self, n):
        while len(self._recv_buf) < n:
            chunk = self.sock.recv(max(4096, n))
            if not chunk:
                raise WSClosed("connection closed")
            self._recv_buf += chunk
        data, self._recv_buf = self._recv_buf[:n], self._recv_buf[n:]
        return data

    def send_text(self, text):
        payload = text.encode("utf-8")
        self._send_frame(0x1, payload)

    def send_pong(self, payload=b""):
        self._send_frame(0xA, payload)

    def send_close(self, code=1000, reason=b""):
        try:
            body = struct.pack("!H", code) + reason
            self._send_frame(0x8, body)
        except (OSError, WSClosed):
            pass

    def _send_frame(self, opcode, payload):
        mask = os.urandom(4)
        masked = bytes(b ^ mask[i % 4] for i, b in enumerate(payload))
        first = 0x80 | (opcode & 0x0F)  # FIN set, no fragmentation on send
        length = len(payload)
        if length <= 125:
            header = struct.pack("!BB", first, 0x80 | length)
        elif length <= 0xFFFF:
            header = struct.pack("!BBH", first, 0x80 | 126, length)
        else:
            header = struct.pack("!BBQ", first, 0x80 | 127, length)
        with self._send_lock:
            self.sock.sendall(header + mask + masked)

    def recv_frame(self):
        """Read one logical message, reassembling continuation fragments.
        Returns (opcode, payload_bytes) for the first frame's opcode, or
        raises WSClosed. Ping/pong/close are returned as-is (opcode intact);
        caller handles them."""
        parts = []
        first_opcode = None
        while True:
            hdr = self._recv_exact(2)
            b0, b1 = hdr[0], hdr[1]
            fin = (b0 & 0x80) != 0
            opcode = b0 & 0x0F
            masked = (b1 & 0x80) != 0
            length = b1 & 0x7F
            if length == 126:
                length = struct.unpack("!H", self._recv_exact(2))[0]
            elif length == 127:
                length = struct.unpack("!Q", self._recv_exact(8))[0]
            mask_key = self._recv_exact(4) if masked else None
            payload = self._recv_exact(length) if length else b""
            if mask_key:
                payload = bytes(
                    b ^ mask_key[i % 4] for i, b in enumerate(payload)
                )
            if opcode in (0x8, 0x9, 0xA):
                # control frames are never fragmented; return immediately
                return opcode, payload
            if opcode != 0x0:
                first_opcode = opcode
            parts.append(payload)
            if fin:
                return first_opcode, b"".join(parts)

    def close(self):
        if self.sock is None:
            return
        try:
            self.send_close()
        except Exception:
            pass
        try:
            self.sock.close()
        except Exception:
            pass
        self.sock = None


# ---------------------------------------------------------------------------
# holder state
# ---------------------------------------------------------------------------


class Holder(object):
    def __init__(self):
        self.token = None
        self.shell_token = None
        self.ws = None
        self.connected = False
        self.since = None
        self.ping_n = 0
        self.last_rtt_ms = None
        self.reconnects = 0
        self.start_time = time.time()
        self.lock = threading.RLock()
        self.pending = {}  # id -> {"event": Event, "frame": dict or None}
        self.stop_flag = threading.Event()
        self.writer_lock = threading.Lock()
        self.last_frame_ts = 0.0
        self.ping_sent_ts = {}

    # -- persistence -----------------------------------------------------

    def load_state(self):
        try:
            with open(STATE_PATH) as f:
                st = json.load(f)
            self.since = st.get("since")
            self.ping_n = st.get("ping_n", 0)
        except (OSError, ValueError):
            pass

    def save_state(self):
        tmp = STATE_PATH + ".tmp"
        with open(tmp, "w") as f:
            json.dump({"since": self.since, "ping_n": self.ping_n}, f)
        os.replace(tmp, STATE_PATH)

    # -- spool -------------------------------------------------------------

    def spool_count(self):
        try:
            return len(
                [n for n in os.listdir(SPOOL_DIR) if n.endswith(".json")]
            )
        except OSError:
            return 0

    def spool_write(self, op):
        ts = time.strftime(
            "%Y-%m-%dT%H-%M-%S", time.gmtime()
        ) + "-%06dZ" % int((time.time() % 1) * 1e6)
        name = "%s-%s.json" % (ts, op["id"])
        path = os.path.join(SPOOL_DIR, name)
        tmp = path + ".tmp"
        with open(tmp, "w") as f:
            json.dump(op, f)
        os.replace(tmp, path)
        return path

    def spool_replay(self):
        try:
            names = sorted(
                n for n in os.listdir(SPOOL_DIR) if n.endswith(".json")
            )
        except OSError:
            return
        for name in names:
            if self.stop_flag.is_set():
                return
            path = os.path.join(SPOOL_DIR, name)
            try:
                with open(path) as f:
                    op = json.load(f)
            except (OSError, ValueError):
                continue
            try:
                final = self._send_and_wait(op, REPLAY_TIMEOUT_S)
            except WSClosed:
                log("replay: socket died mid-replay, stopping")
                return
            if final is None:
                log("replay: %s timed out, leaving in spool" % op.get("id"))
                continue
            ok = final.get("ok")
            dedupe = final.get("dedupe")
            log(
                "replayed %s ok=%s dedupe=%s"
                % (op.get("id"), ok, dedupe)
            )
            try:
                os.makedirs(SPOOL_DONE_DIR, exist_ok=True)
                os.replace(path, os.path.join(SPOOL_DONE_DIR, name))
            except OSError:
                pass

    # -- connection lifecycle ---------------------------------------------

    def note_frame(self):
        self.last_frame_ts = time.time()

    def is_dead(self):
        if not self.connected:
            return True
        return (time.time() - self.last_frame_ts) > DEAD_AFTER_S

    def connect_once(self):
        ws = WSClient(HOLDER_URL)
        ws.connect()
        hello = {
            "hello": HOLDER_SESSION,
            "since": self.since,
            "token": self.token,
        }
        if self.shell_token:
            hello["shell_token"] = self.shell_token
        ws.send_text(json.dumps(hello))
        opcode, payload = ws.recv_frame()
        if opcode != 0x1:
            ws.close()
            raise WSClosed("no text reply to hello")
        try:
            reply = json.loads(payload.decode("utf-8"))
        except ValueError:
            ws.close()
            raise WSClosed("hello reply not JSON")
        if reply.get("hello") is not True:
            log("hello rejected")
            ws.close()
            raise WSClosed("hello rejected")
        acks = reply.get("acks") or []
        log("up (acks=%d)" % len(acks))
        with self.lock:
            self.ws = ws
            self.connected = True
        self.note_frame()
        # start reading incoming frames now, before anything (e.g. spool
        # replay) sends and waits on this socket
        reader = threading.Thread(target=self._reader_loop, args=(ws,), daemon=True)
        reader.start()
        return ws

    def run_forever(self):
        self.load_state()
        try:
            os.makedirs(SPOOL_DIR, mode=0o700, exist_ok=True)
            os.makedirs(SPOOL_DONE_DIR, mode=0o700, exist_ok=True)
        except OSError:
            pass
        attempt = 0
        ever_connected = False
        while not self.stop_flag.is_set():
            try:
                ws = self.connect_once()
                attempt = 0
                if ever_connected:
                    self.reconnects += 1
                ever_connected = True
            except Exception as e:
                with self.lock:
                    self.connected = False
                delay = BACKOFF_STEPS[min(attempt, len(BACKOFF_STEPS) - 1)]
                jittered = random.uniform(0, delay)
                log(
                    "away (attempt %d, retry in %.1fs): %s"
                    % (attempt + 1, jittered, e)
                )
                attempt += 1
                if self.stop_flag.wait(jittered):
                    return
                continue

            self.spool_replay()
            self._pump(ws)
            with self.lock:
                self.connected = False
            if not self.stop_flag.is_set():
                log("connection lost, reconnecting")

    def _pump(self, ws):
        # reader thread is already running (started in connect_once); this
        # loop just drives the liveness ping and dead-socket detection
        last_ping = time.time()
        while not self.stop_flag.is_set():
            if ws is not self.ws:
                return
            if self.is_dead():
                log("no frames for %ds, declaring dead" % DEAD_AFTER_S)
                self._teardown(ws)
                return
            now = time.time()
            if now - last_ping >= PING_INTERVAL_S:
                self.ping_n += 1
                self.ping_sent_ts[self.ping_n] = now
                try:
                    ws.send_text(json.dumps({"ping": self.ping_n}))
                except (OSError, WSClosed):
                    self._teardown(ws)
                    return
                last_ping = now
            time.sleep(0.5)
        self._teardown(ws)

    def _teardown(self, ws):
        with self.lock:
            if self.ws is ws:
                self.connected = False
                self.ws = None
        try:
            ws.close()
        except Exception:
            pass
        # release anyone waiting; they'll fail as "away" via submit's own check
        with self.lock:
            for pid, slot in list(self.pending.items()):
                slot["event"].set()

    def _reader_loop(self, ws):
        try:
            while True:
                opcode, payload = ws.recv_frame()
                if opcode is None:
                    continue
                self.note_frame()
                if opcode == 0x8:  # close
                    log("server sent close frame")
                    self._teardown(ws)
                    return
                if opcode == 0x9:  # ping -> pong
                    try:
                        ws.send_pong(payload)
                    except (OSError, WSClosed):
                        self._teardown(ws)
                        return
                    continue
                if opcode == 0xA:  # WS-level pong control frame; liveness only
                    continue
                if opcode != 0x1:
                    continue
                try:
                    frame = json.loads(payload.decode("utf-8"))
                except ValueError:
                    continue
                self._route(frame)
        except WSClosed:
            self._teardown(ws)
        except Exception as e:
            log("reader loop error: %s" % e)
            self._teardown(ws)

    def _route(self, frame):
        if "pong" in frame:
            self._handle_pong(frame)
            return
        fid = frame.get("id")
        if fid is None:
            log("unmatched frame, keys=%s" % list(frame.keys()))
            return
        with self.lock:
            slot = self.pending.get(fid)
        if slot is None:
            log("unmatched frame for unknown id, keys=%s" % list(frame.keys()))
            return
        is_final = (
            "ok" in frame or frame.get("buffered") is True or frame.get("dedupe") is True
        )
        with self.lock:
            slot["frame"] = frame
        if is_final:
            self._mark_final(fid, frame)
            slot["event"].set()
        elif frame.get("accepted") is True:
            if slot.get("release_on_accept"):
                slot["event"].set()
            # else: interim, keep waiting for the real final frame

    def _handle_pong(self, frame):
        n = frame.get("pong")
        sent = self.ping_sent_ts.pop(n, None) if n is not None else None
        if sent is not None:
            self.last_rtt_ms = (time.time() - sent) * 1000.0

    def _mark_final(self, fid, frame):
        self.since = fid
        self.save_state()

    # -- submit path ---------------------------------------------------

    def _send_and_wait(self, op, timeout, release_on_accept=False):
        """Send op (already has id) over the live socket and wait for its
        terminal frame (final, or accepted if release_on_accept). Raises
        WSClosed if the socket isn't up or the send fails."""
        with self.lock:
            ws = self.ws
            if ws is None or not self.connected:
                raise WSClosed("not connected")
            ev = threading.Event()
            self.pending[op["id"]] = {
                "event": ev,
                "frame": None,
                "release_on_accept": release_on_accept,
            }
        try:
            ws.send_text(json.dumps(op))
        except (OSError, Exception) as e:
            with self.lock:
                self.pending.pop(op["id"], None)
            raise WSClosed("send failed: %s" % e)
        got = ev.wait(timeout)
        with self.lock:
            slot = self.pending.pop(op["id"], None)
        if not got:
            return None
        frame = slot["frame"] if slot else None
        if frame is None:
            # socket died while waiting
            raise WSClosed("connection dropped while waiting")
        return frame

    def submit(self, op, timeout):
        op = dict(op)
        if "id" not in op:
            op["id"] = str(uuid.uuid4())
        oid = op["id"]
        wait_flag = op.pop("wait", True)
        action = op.get("action")
        is_orch = action in ORCH_ACTIONS

        with self.lock:
            up = self.connected and self.ws is not None

        if not up:
            if is_orch:
                return {"ok": False, "error": "away", "id": oid}
            path = self.spool_write(op)
            n = self.spool_count()
            log("spooled %s (%s)" % (oid, os.path.basename(path)))
            return {"queued": True, "id": oid, "spool": n}

        try:
            frame = self._send_and_wait(op, timeout, release_on_accept=not wait_flag)
        except WSClosed as e:
            if is_orch:
                return {"ok": False, "error": "away", "id": oid}
            path = self.spool_write(op)
            n = self.spool_count()
            log("spooled %s after send failure: %s" % (oid, e))
            return {"queued": True, "id": oid, "spool": n}

        if frame is None:
            return {"ok": False, "error": "timeout", "id": oid}
        return frame

    def status(self):
        with self.lock:
            connected = self.connected
        return {
            "connected": connected,
            "mac": "up" if connected else "away",
            "since": self.since,
            "spool": self.spool_count(),
            "last_rtt_ms": self.last_rtt_ms,
            "uptime_s": time.time() - self.start_time,
            "connect_host": HOLDER_CONNECT_HOST,
            "session": HOLDER_SESSION,
            "reconnects": self.reconnects,
            "url": HOLDER_URL,
        }

    def shutdown(self):
        self.stop_flag.set()
        with self.lock:
            ws = self.ws
            self.connected = False
            self.ws = None
        if ws is not None:
            try:
                ws.close()
            except Exception:
                pass
        for slot in list(self.pending.values()):
            slot["event"].set()


# ---------------------------------------------------------------------------
# IPC server (unix socket, one request per connection, thread per connection)
# ---------------------------------------------------------------------------

_holder = None  # set in serve()


class IPCHandler(socketserver.BaseRequestHandler):
    def handle(self):
        try:
            data = b""
            self.request.settimeout(30)
            while b"\n" not in data:
                chunk = self.request.recv(65536)
                if not chunk:
                    break
                data += chunk
            line = data.split(b"\n", 1)[0]
            if not line.strip():
                return
            try:
                req = json.loads(line.decode("utf-8"))
            except ValueError:
                resp = {"ok": False, "error": "bad request"}
                self._write(resp)
                return

            if "ctl" in req:
                resp = self._handle_ctl(req)
            elif "action" in req:
                timeout = req.pop("timeout", 10.0)
                try:
                    timeout = float(timeout)
                except (TypeError, ValueError):
                    timeout = 10.0
                resp = _holder.submit(req, timeout)
            else:
                resp = {"ok": False, "error": "bad request"}
            self._write(resp)
        except Exception as e:
            try:
                self._write({"ok": False, "error": "internal error: %s" % e})
            except Exception:
                pass

    def _handle_ctl(self, req):
        what = req.get("ctl")
        if what == "status":
            return _holder.status()
        if what == "stop":
            threading.Thread(target=_do_stop, daemon=True).start()
            return {"ok": True}
        return {"ok": False, "error": "bad request"}

    def _write(self, obj):
        self.request.sendall((json.dumps(obj) + "\n").encode("utf-8"))


class IPCServer(socketserver.ThreadingUnixStreamServer):
    daemon_threads = True
    allow_reuse_address = True


def _do_stop():
    time.sleep(0.2)  # let the {"ok": true} reply flush first
    _holder.shutdown()
    try:
        os.remove(SOCK_PATH)
    except OSError:
        pass
    os._exit(0)


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------


def cmd_serve():
    global _holder
    os.makedirs(HOLDER_DIR, mode=0o700, exist_ok=True)
    token = load_token()
    _set_token_for_guard(token)
    shell_token = load_shell_token()

    _holder = Holder()
    _holder.token = token
    _holder.shell_token = shell_token

    if os.path.exists(SOCK_PATH):
        try:
            os.remove(SOCK_PATH)
        except OSError:
            pass

    server = IPCServer(SOCK_PATH, IPCHandler)
    os.chmod(SOCK_PATH, 0o600)

    ws_thread = threading.Thread(target=_holder.run_forever, daemon=True)
    ws_thread.start()

    def _signal_handler(signum, frame):
        log("signal %d received, shutting down" % signum)
        _holder.shutdown()
        try:
            server.shutdown()
        except Exception:
            pass
        try:
            os.remove(SOCK_PATH)
        except OSError:
            pass
        os._exit(0)

    import signal

    signal.signal(signal.SIGTERM, _signal_handler)
    signal.signal(signal.SIGINT, _signal_handler)

    log("serving on %s, dialing %s" % (SOCK_PATH, HOLDER_URL))
    server.serve_forever()


def submit(op, timeout=10.0, sock=None):
    """Importable helper for other scripts: one JSON line in, one JSON line out.
    `sock` overrides the unix-socket path (default SOCK_PATH, honouring HOLDER_DIR)."""
    req = dict(op)
    req["timeout"] = timeout
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.settimeout(timeout + 5)
    s.connect(sock or SOCK_PATH)
    s.sendall((json.dumps(req) + "\n").encode("utf-8"))
    s.shutdown(socket.SHUT_WR)
    data = b""
    while b"\n" not in data:
        chunk = s.recv(65536)
        if not chunk:
            break
        data += chunk
    s.close()
    return json.loads(data.split(b"\n", 1)[0].decode("utf-8"))


def _ipc_call(req, timeout=15.0):
    return submit(req, timeout)


def cmd_send(argv):
    if not argv:
        sys.stderr.write("usage: wss-holder.py send '<json>' [--timeout S]\n")
        sys.exit(2)
    body = argv[0]
    timeout = 10.0
    if "--timeout" in argv:
        i = argv.index("--timeout")
        timeout = float(argv[i + 1])
    try:
        op = json.loads(body)
    except ValueError as e:
        sys.stderr.write("bad JSON: %s\n" % e)
        sys.exit(2)
    op["timeout"] = timeout
    try:
        resp = _ipc_call(op, timeout=timeout)
    except (OSError, socket.timeout) as e:
        print(json.dumps({"ok": False, "error": "ipc error: %s" % e}))
        sys.exit(1)
    print(json.dumps(resp))
    if resp.get("ok") is True or resp.get("queued") is True:
        sys.exit(0)
    sys.exit(1)


def cmd_status():
    try:
        resp = _ipc_call({"ctl": "status"}, timeout=5)
    except (OSError, socket.timeout) as e:
        print(json.dumps({"connected": False, "error": "ipc error: %s" % e}))
        sys.exit(1)
    print(json.dumps(resp))


def cmd_stop():
    try:
        resp = _ipc_call({"ctl": "stop"}, timeout=5)
    except (OSError, socket.timeout) as e:
        print(json.dumps({"ok": False, "error": "ipc error: %s" % e}))
        sys.exit(1)
    print(json.dumps(resp))


def main():
    if len(sys.argv) < 2:
        sys.stderr.write(
            "usage: wss-holder.py serve|send|status|stop [args]\n"
        )
        sys.exit(2)
    cmd = sys.argv[1]
    if cmd == "serve":
        cmd_serve()
    elif cmd == "send":
        cmd_send(sys.argv[2:])
    elif cmd == "status":
        cmd_status()
    elif cmd == "stop":
        cmd_stop()
    else:
        sys.stderr.write("unknown command: %s\n" % cmd)
        sys.exit(2)


if __name__ == "__main__":
    main()
