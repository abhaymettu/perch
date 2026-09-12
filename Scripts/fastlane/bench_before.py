#!/usr/bin/env python3
"""The per-command cold path a cloud caller pays today, one verb at a time:
  (1) ssh handshake to the Mac for the token (relayed),
  (2) cold TLS + WSS upgrade + hello,
  (3) one device verb with readback.
Also times a cold per-request HTTPS call (curl --resolve) for comparison.

  bench_before.py [--n 5] [--connect-host IP] [--ssh-cmd "..."] [--out f.json]

Run from the Mac with --connect-host <public ingress IP> so the path is relayed, or from
the cloud with no pin. Uses brightness.get only. Stdlib only, python 3.9+.
"""
import argparse, json, os, statistics, subprocess, sys, time, uuid
from urllib.parse import urlsplit

HERE = os.path.dirname(os.path.abspath(__file__))


def recv_text(ws):
    while True:
        opcode, payload = ws.recv_frame()
        if opcode == 0x1:
            return payload.decode("utf-8")


from bench_classify import load_module, pct


def summarise(xs):
    return {"p50": pct(xs, 50), "p95": pct(xs, 95), "mean": statistics.mean(xs), "min": min(xs), "max": max(xs)}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--n", type=int, default=5)
    ap.add_argument("--url", default=os.environ.get("HOLDER_URL", "wss://abhays-macbook-pro.tail4948a2.ts.net:10000/v1/ctl"))
    ap.add_argument("--connect-host", default=os.environ.get("HOLDER_CONNECT_HOST"))
    ap.add_argument("--token-file", default=os.path.expanduser("~/.perch-bridge/device.token"))
    ap.add_argument("--ssh-cmd", help="shell command that fetches the token over ssh; timed as leg 1. "
                    "Default on the Mac: an ssh handshake to the funnel that stops at auth (no key to self).")
    ap.add_argument("--out")
    a = ap.parse_args()
    if a.connect_host:
        os.environ["HOLDER_CONNECT_HOST"] = a.connect_host
    holder = load_module(os.path.join(HERE, "..", "wss-holder.py"), "wss_holder")
    token = open(a.token_file).read().strip()
    host = urlsplit(a.url).hostname
    port = urlsplit(a.url).port
    ssh_cmd = a.ssh_cmd or (
        "ssh -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "
        "-o ProxyCommand='openssl s_client -quiet -connect %s:8443 -servername %s 2>/dev/null' abhay@%s true"
        % (a.connect_host or host, host, host))

    legs = {"ssh_ms": [], "dial_ms": [], "verb_ms": [], "total_ms": [], "https_cold_ms": []}
    for i in range(a.n):
        t0 = time.perf_counter()
        subprocess.run(ssh_cmd, shell=True, capture_output=True, timeout=30)
        t1 = time.perf_counter()
        ws = holder.WSClient(a.url)
        ws.connect()
        ws.send_text(json.dumps({"hello": "bench-before-%d" % i, "since": None, "token": token}))
        hello = json.loads(recv_text(ws))
        if not hello.get("hello"):
            sys.exit("hello rejected")
        t2 = time.perf_counter()
        ws.send_text(json.dumps({"id": str(uuid.uuid4()), "action": "brightness.get"}))
        res = json.loads(recv_text(ws))
        t3 = time.perf_counter()
        ws.close()
        if not res.get("ok"):
            sys.exit("verb failed: %s" % json.dumps(res))
        legs["ssh_ms"].append((t1 - t0) * 1000)
        legs["dial_ms"].append((t2 - t1) * 1000)
        legs["verb_ms"].append((t3 - t2) * 1000)
        legs["total_ms"].append((t3 - t0) * 1000)
        curl = ["curl", "-s", "-o", "/dev/null", "-w", "%{time_total}", "-m", "15",
                "-H", "Authorization: Bearer " + token, "-H", "Content-Type: application/json",
                "-d", json.dumps([{"id": str(uuid.uuid4()), "action": "brightness.get"}]),
                "https://%s:%d/v1/batch" % (host, port)]
        if a.connect_host:
            curl[1:1] = ["--resolve", "%s:%d:%s" % (host, port, a.connect_host)]
        out = subprocess.run(curl, capture_output=True, text=True, timeout=20).stdout.strip()
        legs["https_cold_ms"].append(float(out) * 1000)

    summary = {k: summarise(v) for k, v in legs.items()}
    print("| leg | p50 ms | p95 ms | mean ms | min | max |")
    print("|---|---|---|---|---|---|")
    for k, s in summary.items():
        print("| %s | %.0f | %.0f | %.0f | %.0f | %.0f |" % (k, s["p50"], s["p95"], s["mean"], s["min"], s["max"]))
    if a.out:
        with open(a.out, "w") as f:
            json.dump({"n": a.n, "connect_host": a.connect_host, "summary": summary, "legs": legs}, f, indent=1)


if __name__ == "__main__":
    main()
