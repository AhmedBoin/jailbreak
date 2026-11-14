#!/usr/bin/env python3
"""Spawn IDMan.exe under Frida and report the license status code and dialogs.

Usage:
    python hook-status.py <IDMan.exe> [--seconds 8] [--dispatcher 0x50630]
                          [--wrapper 0x6D5C0]

The dispatcher and wrapper RVAs default to the 6.43 build 18 values. For any
other build, pass the values you found in section 2 of the playbook. The
dispatcher RVA is the function that returns the license status code; the
wrapper is the function that shows the encrypted ``IDM_emc_...`` message boxes.

Install Frida before use:  python -m pip install frida
"""

import argparse
import json
import sys
import time
from pathlib import Path

try:
    import frida
except ImportError:
    print("frida is not installed: python -m pip install frida")
    raise SystemExit(2)


def on_message(message, data):
    if message.get("type") != "send":
        print("[frida-error] %s" % json.dumps(message)[:400], flush=True)
        return
    payload = message.get("payload", {})
    kind = payload.get("kind")

    if kind == "status":
        if payload.get("phase") == "leave":
            print(
                "[STATUS] t=%ss code=%d" % (payload["ts"], payload["code"]), flush=True
            )
    elif kind == "messagebox":
        print(
            "[MSGBOX] t=%ss type=%s caption=%r text=%r"
            % (
                payload["ts"],
                payload["type"],
                payload.get("caption"),
                payload.get("text"),
            ),
            flush=True,
        )
        print("         %s" % payload.get("bt"), flush=True)
    elif kind == "dialog":
        print(
            "[DIALOG] t=%ss template=%s proc=%s"
            % (payload["ts"], payload.get("template"), payload.get("proc")),
            flush=True,
        )
        print("         %s" % payload.get("bt"), flush=True)
    elif kind == "call":
        print(
            "[EXIT? ] t=%ss %s code=%s"
            % (payload["ts"], payload["api"], payload.get("code")),
            flush=True,
        )
        print("         %s" % payload.get("bt"), flush=True)
    elif kind == "hooked":
        print("[hook] %s" % payload.get("api"), flush=True)
    elif kind == "missing":
        print("[skip] %s not imported" % payload.get("api"), flush=True)
    elif kind == "ready":
        print(
            "[ready] pid=%s base=%s" % (payload.get("pid"), payload.get("base")),
            flush=True,
        )


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("exe")
    ap.add_argument("--seconds", type=float, default=8.0)
    ap.add_argument("--dispatcher", default="0x50630")
    ap.add_argument("--wrapper", default="0x6D5C0")
    ap.add_argument("--no-wrapper", action="store_true")
    args = ap.parse_args()

    exe = Path(args.exe).resolve()
    if not exe.exists():
        print("missing executable: %s" % exe)
        return 2

    script_path = Path(__file__).with_name("hook-status.js")
    source = script_path.read_text(encoding="utf-8")

    pid = frida.spawn(str(exe))
    print("[spawn] pid=%d" % pid, flush=True)
    session = frida.attach(pid)
    script = session.create_script(source)
    script.on("message", on_message)
    script.load()

    dispatcher = int(args.dispatcher, 0)
    script.exports_sync.set_dispatcher(dispatcher)
    if not args.no_wrapper:
        script.exports_sync.set_wrapper(int(args.wrapper, 0))

    frida.resume(pid)
    print("[resume] watching %.1fs" % args.seconds, flush=True)
    time.sleep(args.seconds)

    alive = True
    try:
        session.detach()
    except Exception:
        alive = False
    print("[result] alive_after_probe=%s" % alive, flush=True)
    print(
        "[hint] code 0 means registered. Any other code is the branch to patch.",
        flush=True,
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
