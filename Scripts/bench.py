#!/usr/bin/env python3
"""Measure what Perch costs the Mac it runs on.

Builds a Release copy under its own bundle id (com.abhaymettu.perch.bench), so
an installed Perch is never touched, hides its status item, runs it for a
while with the panel closed, and prints one JSON line:

  cpu_pct        CPU time / wall time over its whole life, Perch plus every
                 scanner it spawned (ps, lsof, simctl, launchctl, crontab)
  cpu_self_pct   Perch's own process only, steady state (after the first 10 s)
  footprint_mb   physical footprint at the end of the run (what Activity Monitor shows)
  wakeups_per_s  wakeups per second (proc_pid_rusage), steady state

The status item is hidden, which on its own would stop the owl's idle motion
(Perch skips it when nobody can see the menu bar). --owl measures the owl
idling as if the menu bar were on screen.

Usage: Scripts/bench.py [seconds] [--owl] [--no-build]
"""
import ctypes
import json
import os
import re
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


class RusageInfoV2(ctypes.Structure):
    _fields_ = [("uuid", ctypes.c_uint8 * 16)] + [(name, ctypes.c_uint64) for name in (
        "user_time", "system_time", "pkg_idle_wkups", "interrupt_wkups", "pageins", "wired_size",
        "resident_size", "phys_footprint", "proc_start_abstime", "proc_exit_abstime", "child_user_time",
        "child_system_time", "child_pkg_idle_wkups", "child_interrupt_wkups", "child_pageins",
        "child_elapsed_abstime", "diskio_bytesread", "diskio_byteswritten")]


def wakeups(pid):
    """Interrupt wakeups the kernel counted for the process."""
    info = RusageInfoV2()
    libproc = ctypes.CDLL("/usr/lib/libproc.dylib")
    if libproc.proc_pid_rusage(pid, 2, ctypes.byref(info)) != 0:
        return None
    # pkg_idle_wkups is a subset of these, so it is not added on top.
    return info.interrupt_wkups


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    seconds = int(args[0]) if args else 300
    if "--no-build" not in sys.argv:
        build()

    defaults("hasLaunchedBefore", "-bool", "true")
    defaults("NSStatusItem Visible Perch", "-bool", "false")

    launched = time.monotonic()
    env = dict(os.environ)
    if "--owl" in sys.argv:
        env["PERCH_BENCH_OWL_VISIBLE"] = "1"
    proc = subprocess.Popen([APP], env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(10)  # launch and the first scan are not steady state
    start_cpu, start, start_wake = cpu_seconds(proc.pid), time.monotonic(), wakeups(proc.pid)

    time.sleep(seconds)
    wake = (wakeups(proc.pid) - start_wake) / (time.monotonic() - start)
    self_cpu = cpu_seconds(proc.pid) - start_cpu
    elapsed = time.monotonic() - start
    foot = footprint_mb(proc.pid)

    proc.send_signal(signal.SIGTERM)
    # wait4 returns Perch's own rusage, which covers its whole life (launch
    # included) plus every scanner it spawned and reaped, and nothing this
    # script ran itself, such as the build.
    _, _, usage = os.wait4(proc.pid, 0)
    lifetime = time.monotonic() - launched

    print(json.dumps({
        "seconds": round(elapsed),
        "owl_idling": "--owl" in sys.argv,
        "cpu_pct": round(100 * (usage.ru_utime + usage.ru_stime) / lifetime, 2),
        "cpu_self_pct": round(100 * self_cpu / elapsed, 2),
        "footprint_mb": foot,
        "wakeups_per_s": round(wake, 2),
    }))


if __name__ == "__main__":
    main()
