#!/usr/bin/env python3
"""Measure what Perch costs the Mac it runs on.

Builds a Release copy under its own bundle id (com.abhaymettu.perch.bench), so
an installed Perch is never touched, hides its status item, runs it for a
while with the panel closed, and prints one JSON line:

  cpu_pct        CPU time / wall time over its whole life, Perch plus every
                 scanner it spawned (ps, lsof, simctl, launchctl, crontab)
  cpu_self_pct   Perch's own process only, steady state (after the first 10 s)
  footprint_mb   physical footprint at the end of the run (what Activity Monitor shows)
  wakeups_per_s  idle wakeups per second, averaged over the run

Usage: Scripts/bench.py [seconds] [--no-build]
"""
import json
import os
import re
import resource
import signal
import subprocess
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BUNDLE = "com.abhaymettu.perch.bench"
DERIVED = os.path.join(ROOT, "build", "bench")
APP = os.path.join(DERIVED, "Build/Products/Release/Perch.app/Contents/MacOS/Perch")


def build():
    subprocess.run(
        ["xcodebuild", "-project", "Perch.xcodeproj", "-scheme", "Perch", "-configuration", "Release",
         "-derivedDataPath", DERIVED, f"PRODUCT_BUNDLE_IDENTIFIER={BUNDLE}", "build"],
        cwd=ROOT, check=True, stdout=subprocess.DEVNULL,
    )


def defaults(key, kind, value):
    subprocess.run(["defaults", "write", BUNDLE, key, kind, value], check=True)


def cpu_seconds(pid):
    out = subprocess.run(["ps", "-o", "time=", "-p", str(pid)], capture_output=True, text=True).stdout.strip()
    parts = [float(p) for p in re.split("[:]", out)]
    total = 0.0
    for p in parts:
        total = total * 60 + p
    return total


def footprint_mb(pid):
    out = subprocess.run(["footprint", "-p", str(pid)], capture_output=True, text=True).stdout
    m = re.search(r"Footprint:\s+([\d.]+)\s+(KB|MB|GB)", out)
    if not m:
        return None
    scale = {"KB": 1 / 1024, "MB": 1, "GB": 1024}[m.group(2)]
    return round(float(m.group(1)) * scale, 1)


def wakeups_per_s(pid, seconds):
    samples = max(2, seconds // 10)
    out = subprocess.run(
        ["top", "-l", str(samples + 1), "-s", "10", "-pid", str(pid), "-stats", "pid,idlew"],
        capture_output=True, text=True,
    ).stdout
    counts = [int(m.group(1)) for m in re.finditer(rf"^{pid}\s+(\d+)", out, re.M)]
    # The first sample counts from process start, not over an interval.
    counts = counts[1:]
    return round(sum(counts) / (10 * len(counts)), 2) if counts else None


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    seconds = int(args[0]) if args else 300
    if "--no-build" not in sys.argv:
        build()

    defaults("hasLaunchedBefore", "-bool", "true")
    defaults("NSStatusItem Visible Perch", "-bool", "false")

    launched = time.monotonic()
    proc = subprocess.Popen([APP], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(10)  # launch and the first scan are not steady state
    start_cpu, start = cpu_seconds(proc.pid), time.monotonic()

    wake = wakeups_per_s(proc.pid, seconds)
    self_cpu = cpu_seconds(proc.pid) - start_cpu
    elapsed = time.monotonic() - start
    foot = footprint_mb(proc.pid)

    proc.send_signal(signal.SIGTERM)
    proc.wait()
    lifetime = time.monotonic() - launched
    # Perch's rusage reaches us only at exit, and it covers its whole life:
    # launch, steady state, and every scanner it spawned and reaped. So this
    # figure is over the whole lifetime, launch included.
    usage = resource.getrusage(resource.RUSAGE_CHILDREN)

    print(json.dumps({
        "seconds": round(elapsed),
        "cpu_pct": round(100 * (usage.ru_utime + usage.ru_stime) / lifetime, 2),
        "cpu_self_pct": round(100 * self_cpu / elapsed, 2),
        "footprint_mb": foot,
        "wakeups_per_s": wake,
    }))


if __name__ == "__main__":
    main()
