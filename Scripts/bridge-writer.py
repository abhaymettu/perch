#!/usr/bin/env python3
"""Bridge status writer for Perch.

Polls `herdr pane/tab/workspace list` (the SSH+tmux agent lane's local
viewer) and writes a small JSON snapshot Perch reads to show one row per
live task. Replaces the retired exec-poller lane entirely — see vault
05-Bridge/lane-cutover-2026-09-06.md.

Runs as a loop in its own tmux window inside the existing "agent" session,
not as a launchd daemon: nothing supervises it beyond that, matching every
other window in this lane. Restart it by hand if the window or tmux server
dies:

    tmux new-window -t agent -n bridge-writer 'python3 ~/Desktop/Playground/perch/Scripts/bridge-writer.py'
"""

import json
import os
import subprocess
import tempfile
import time

HERDR = "/opt/homebrew/bin/herdr"
OUT_DIR = os.path.expanduser("~/.perch-bridge")
OUT_FILE = os.path.join(OUT_DIR, "status.json")
POLL_SECS = 5


def herdr_json(*args):
    result = subprocess.run([HERDR, *args], capture_output=True, text=True, timeout=10)
    return json.loads(result.stdout)["result"]


def status_text_from_title(title):
    # "view-kalshi:4:kalshi - \"✳ Kalshi reflex worker Phase A implementation\""
    start = title.find('"')
    end = title.rfind('"')
    if start != -1 and end > start:
        return title[start + 1:end]
    return None


def build_tasks():
    workspaces = {w["workspace_id"]: w["label"] for w in herdr_json("workspace", "list")["workspaces"]}
    tabs = {t["tab_id"]: t for t in herdr_json("tab", "list")["tabs"]}
    panes = herdr_json("pane", "list")["panes"]

    tasks = []
    for pane in panes:
        tab_id = pane["tab_id"]
        tab = tabs.get(tab_id)
        if tab is None:
            continue
        tasks.append({
            "tab_id": tab_id,
            "workspace_id": pane["workspace_id"],
            "workspace_label": workspaces.get(pane["workspace_id"], pane["workspace_id"]),
            "tab_label": tab["label"],
            "status_text": status_text_from_title(pane.get("terminal_title_stripped", "")),
            "updated_at": time.time(),
        })
    return tasks


def write_atomic(snapshot):
    os.makedirs(OUT_DIR, exist_ok=True)
    fd, tmp_path = tempfile.mkstemp(dir=OUT_DIR)
    try:
        with os.fdopen(fd, "w") as f:
            json.dump(snapshot, f)
        os.replace(tmp_path, OUT_FILE)
    except Exception:
        if os.path.exists(tmp_path):
            os.remove(tmp_path)
        raise


def main():
    while True:
        try:
            tasks = build_tasks()
            write_atomic({"generated_at": time.time(), "tasks": tasks})
        except Exception as e:
            # A bad poll (herdr restarting, tmux hiccup) should not kill the
            # loop — the next cycle tries again, and a stale file just reads
            # as no bridge rather than crashing Perch's poll.
            print(f"bridge-writer: {e}")
        time.sleep(POLL_SECS)


if __name__ == "__main__":
    main()
