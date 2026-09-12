#!/usr/bin/env python3
"""bench_classify.py -- accuracy + latency harness for classify.py.

    bench_classify.py --set intents.json --mode rules|llm|hybrid
                       [--url URL] [--model MODEL] [--via-holder SOCKPATH]
                       [--out results.json] [--repeat 1]

Runs every item in the test set (see intents.json) through classify(), or
through the cloud holder's `classify` orch verb with --via-holder, and scores
it: a must_fallback item is correct iff the result fell back; a positive item
is correct iff its op exactly matches `expect` (numeric int/float compared by
value). Reports a markdown table + summary to stdout; --out also writes JSON.

Python 3.9+ stdlib only. See docs/fastlane/SPEC.md FR-B and
docs/fastlane/PLAN.md decisions 5-6.
"""
import argparse
import importlib.util
import json
import os
import statistics
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from classify import classify  # noqa: E402


def load_module(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def pct(xs, p):
    """p in 0..100, xs unsorted."""
    xs = sorted(xs)
    return xs[min(len(xs) - 1, int(round(p / 100.0 * (len(xs) - 1))))] if xs else 0.0


def run_local(text, mode, url, model):
    t0 = time.monotonic()
    res = classify(text, mode=mode, url=url, model=model)
    ms = (time.monotonic() - t0) * 1000.0
    return res, ms


def run_via_holder(text, mode, sockpath, holder_mod):
    t0 = time.monotonic()
    frame = holder_mod.submit({"action": "classify", "text": text, "mode": mode},
                               timeout=30, sock=sockpath)
    ms = (time.monotonic() - t0) * 1000.0
    res = frame.get("result") if isinstance(frame, dict) else None
    if not isinstance(res, dict):
        res = {"ok": False, "text": text, "intent": "FALLBACK", "op": None, "fallback": True,
               "tier": "none", "ms": ms, "model": None, "raw": None,
               "error": "no result field in holder frame: " + json.dumps(frame)[:200]}
    return res, ms


def values_equal(a, b):
    if isinstance(a, bool) or isinstance(b, bool):
        return a is b
    if isinstance(a, (int, float)) and isinstance(b, (int, float)):
        return abs(float(a) - float(b)) < 1e-6
    return a == b


def op_equal(a, b):
    if a is None or b is None:
        return a == b
    if not isinstance(a, dict) or not isinstance(b, dict):
        return a == b
    if set(a.keys()) != set(b.keys()):
        return False
    for k in a:
        va, vb = a[k], b[k]
        if isinstance(va, dict) and isinstance(vb, dict):
            if not op_equal(va, vb):
                return False
        elif isinstance(va, list) and isinstance(vb, list):
            if len(va) != len(vb) or any(not values_equal(x, y) for x, y in zip(va, vb)):
                return False
        else:
            if not values_equal(va, vb):
                return False
    return True


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--set", required=True)
    ap.add_argument("--mode", required=True, choices=["rules", "llm", "hybrid"])
    ap.add_argument("--url")
    ap.add_argument("--model")
    ap.add_argument("--via-holder")
    ap.add_argument("--out")
    ap.add_argument("--repeat", type=int, default=1)
    args = ap.parse_args()

    with open(args.set) as f:
        items = json.load(f)
    if not items:
        sys.exit("empty test set: " + args.set)

    holder_mod = load_module(os.path.join(HERE, "..", "wss-holder.py"), "wss_holder") if args.via_holder else None

    def classify_one(text):
        if holder_mod is not None:
            return run_via_holder(text, args.mode, args.via_holder, holder_mod)
        return run_local(text, args.mode, args.url, args.model)

    classify_one(items[0]["text"])  # warm-up, untimed

    rows = []
    for _ in range(max(1, args.repeat)):
        for item in items:
            res, ms = classify_one(item["text"])
            rows.append((item, res, ms))

    pos_total = pos_correct = 0
    neg_total = false_fires = 0
    false_fire_texts = []
    misses = []
    for item, res, ms in rows:
        must_fb = item["must_fallback"]
        if must_fb:
            neg_total += 1
            if not res.get("fallback"):
                false_fires += 1
                false_fire_texts.append(item["text"])
                misses.append({"text": item["text"], "expect": None, "got": res.get("op"),
                               "tier": res.get("tier"), "must_fallback": True})
        else:
            pos_total += 1
            expect = item.get("expect")
            if op_equal(res.get("op"), expect):
                pos_correct += 1
            else:
                misses.append({"text": item["text"], "expect": expect, "got": res.get("op"),
                               "tier": res.get("tier"), "must_fallback": False})

    times = sorted(ms for _, _, ms in rows)
    p50, p95 = pct(times, 50), pct(times, 95)
    mean_ms = statistics.mean(times) if times else 0.0
    max_ms = max(times) if times else 0.0
    pos_pct = (pos_correct / pos_total * 100.0) if pos_total else 0.0

    report = {
        "mode": args.mode, "n": len(rows), "repeat": args.repeat,
        "positives_total": pos_total, "positives_correct": pos_correct, "positives_pct": pos_pct,
        "must_fallback_total": neg_total, "false_fires": false_fires,
        "false_fire_texts": false_fire_texts,
        "latency_ms": {"p50": p50, "p95": p95, "mean": mean_ms, "max": max_ms},
        "misses": misses,
    }

    print("# bench_classify: mode=%s (n=%d, repeat=%d)" % (args.mode, len(rows), args.repeat))
    print()
    print("positives: %d/%d (%.1f%%)   must-fallback false-fires: %d/%d" % (
        pos_correct, pos_total, pos_pct, false_fires, neg_total))
    print("latency ms: p50=%.2f p95=%.2f mean=%.2f max=%.2f" % (p50, p95, mean_ms, max_ms))
    print()
    if false_fire_texts:
        print("false fires (must-fallback items that produced an op):")
        for t in false_fire_texts:
            print("- " + t)
        print()
    if misses:
        print("| text | expect | got | tier |")
        print("|---|---|---|---|")
        for m in misses:
            print("| %s | %s | %s | %s |" % (
                m["text"], json.dumps(m["expect"]), json.dumps(m["got"]), m["tier"]))
    else:
        print("no misses.")

    if args.out:
        with open(args.out, "w") as f:
            json.dump(report, f, indent=2)


if __name__ == "__main__":
    main()
