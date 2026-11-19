#!/usr/bin/env python3
"""Spawn IDMan.exe, trigger the MFC-spawned trial-nag thread, and list IDMan windows.

Usage: python nag-call.py <IDMan.exe> [--wait 8]
"""

import argparse
import json
import time
from pathlib import Path

import frida


def on_message(message, data):
    if message.get("type") != "send":
        print("[frida-error] %s" % json.dumps(message)[:300], flush=True)
        return
    p = message.get("payload", {})
    k = p.get("kind")
    if k == "snapshot":
        wins = [w for w in p["wins"] if "frida" not in w["cls"].lower()]
        print("[snapshot %s] %d windows" % (p.get("tag"), len(wins)), flush=True)
        for w in wins:
            print(
                "    hwnd=%-10s cls=%-30r title=%r" % (w["hwnd"], w["cls"], w["title"]),
                flush=True,
            )
    else:
        print("[%s] %s" % (k, {x: y for x, y in p.items() if x != "kind"}), flush=True)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("exe")
    ap.add_argument("--wait", type=float, default=8.0)
    args = ap.parse_args()

    exe = Path(args.exe).resolve()
    src = Path(__file__).with_name("nag-call.js").read_text(encoding="utf-8")
    pid = frida.spawn(str(exe))
    print("[spawn] pid=%d" % pid, flush=True)
    s = frida.attach(pid)
    sc = s.create_script(src)
    sc.on("message", on_message)
    sc.load()
    frida.resume(pid)
    time.sleep(4.0)
    print("[arm] triggerMfc", flush=True)
    print("  ->", sc.exports_sync.trigger_mfc(), flush=True)
    time.sleep(args.wait)
    print("[after] snapshot", flush=True)
    try:
        sc.exports_sync.snap()
    except Exception as exc:
        print("[gone] script unreachable: %s" % exc, flush=True)
    try:
        s.detach()
    except Exception:
        pass
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
