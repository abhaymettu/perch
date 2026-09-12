#!/usr/bin/env python3
"""Receipt -> readback through the fast lane: classify, holder IPC, held WSS, daemon readback.

  bench_e2e.py --sock ~/.perch-bridge/holder/holder.sock [--n 20] [--mode hybrid|llm|rules] [--out f.json]

Invisible verbs only: reads brightness, then sets it to the value just read. Every
trial reports classify ms, holder round trip ms (IPC + WSS + execute + readback), and
total. Stdlib only, python 3.9+.
"""
import argparse, json, os, statistics, sys, time

HERE = os.path.dirname(os.path.abspath(__file__))


from bench_classify import load_module, pct


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--sock", default=os.path.expanduser("~/.perch-bridge/holder/holder.sock"))
    ap.add_argument("--n", type=int, default=20)
    ap.add_argument("--mode", default="hybrid", choices=["hybrid", "llm", "rules"])
    ap.add_argument("--out")
    a = ap.parse_args()

    holder = load_module(os.path.join(HERE, "..", "wss-holder.py"), "wss_holder")
    clf = load_module(os.path.join(HERE, "classify.py"), "fastlane_classify")

    cur = holder.submit({"action": "brightness.get"}, timeout=10, sock=a.sock)
    if not cur.get("ok"):
        sys.exit("brightness.get failed: %s" % json.dumps(cur))
    rb = cur.get("readback")
    if isinstance(rb, dict):
        rb = rb.get("brightness", rb.get("value"))
    if rb is None:
        sys.exit("no brightness in readback: %s" % json.dumps(cur))
    level = rb
    level = int(round(float(level) * (100 if float(level) <= 1 else 1)))
    texts = ["brightness %d" % level, "what is my brightness"]
    clf.classify(texts[0], mode=a.mode)  # warm the classifier once, untimed

    trials = []
    for i in range(a.n):
        text = texts[i % 2]
        t0 = time.perf_counter()
        c = clf.classify(text, mode=a.mode)
        t1 = time.perf_counter()
        if c.get("fallback") or not c.get("op"):
            trials.append({"text": text, "classify_ms": (t1 - t0) * 1000, "holder_ms": None,
                           "total_ms": None, "ok": False, "error": "classifier fell back"})
            continue
        r = holder.submit(dict(c["op"]), timeout=10, sock=a.sock)
        t2 = time.perf_counter()
        trials.append({"text": text, "op": c["op"], "tier": c.get("tier"),
                       "classify_ms": (t1 - t0) * 1000, "holder_ms": (t2 - t1) * 1000,
                       "total_ms": (t2 - t0) * 1000, "ok": bool(r.get("ok")),
                       "daemon_ms": r.get("ms"), "readback": r.get("readback"),
                       "error": r.get("error")})

    good = [t for t in trials if t["ok"]]
    summary = {"n": len(trials), "ok": len(good), "mode": a.mode, "sock": a.sock}
    for key in ("classify_ms", "holder_ms", "total_ms"):
        xs = [t[key] for t in good if t.get(key) is not None]
        if xs:
            summary[key] = {"p50": pct(xs, 50), "p95": pct(xs, 95), "mean": statistics.mean(xs),
                            "min": min(xs), "max": max(xs)}
    print("| leg | p50 ms | p95 ms | mean ms | min | max |")
    print("|---|---|---|---|---|---|")
    for key in ("classify_ms", "holder_ms", "total_ms"):
        s = summary.get(key)
        if s:
            print("| %s | %.0f | %.0f | %.0f | %.0f | %.0f |" % (key, s["p50"], s["p95"], s["mean"], s["min"], s["max"]))
    print("ok %d/%d, mode %s" % (len(good), len(trials), a.mode))
    for t in trials:
        if not t["ok"]:
            print("FAIL", json.dumps(t))
    if a.out:
        with open(a.out, "w") as f:
            json.dump({"summary": summary, "trials": trials}, f, indent=1)


if __name__ == "__main__":
    main()
