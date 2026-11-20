#!/usr/bin/env python3
"""Spawn IDMan.exe under Frida and log every URL or process launch it performs.

Usage: python buy-probe.py <IDMan.exe> [--seconds 300] [--args ...]
"""

import argparse
import json
import time
from pathlib import Path

import frida


def on_message(message, data):
    if message.get("type") != "send":
        print("[frida-error] %s" % json.dumps(message)[:400], flush=True)
        return
    p = message.get("payload", {})
    kind = p.get("kind")
    if kind in ("hooked", "missing"):
        print("[%-8s] %s" % (kind, p.get("api")), flush=True)
        return
    extra = " ".join(
        "%s=%r" % (k, v) for k, v in p.items() if k not in ("kind", "ts", "bt")
    )
    print("[%-8s] %s" % (kind, extra), flush=True)
    if p.get("bt"):
        print("           %s" % p["bt"], flush=True)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("exe")
    ap.add_argument("--seconds", type=float, default=300.0)
    ap.add_argument("--args", nargs="*", default=[])
    args = ap.parse_args()

    exe = Path(args.exe).resolve()
    source = Path(__file__).with_name("buy-probe.js").read_text(encoding="utf-8")
    pid = frida.spawn([str(exe)] + args.args)
    print("[spawn] pid=%d %s" % (pid, exe), flush=True)
    session = frida.attach(pid)
    script = session.create_script(source)
    script.on("message", on_message)
    script.load()
    frida.resume(pid)
    print("[resume] watching %.1fs" % args.seconds, flush=True)
    try:
        time.sleep(args.seconds)
    except KeyboardInterrupt:
        pass
    try:
        session.detach()
    except Exception:
        pass
    print("[result] done", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
