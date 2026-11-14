#!/usr/bin/env python3
"""Apply a JSON patch manifest to a PE file and recompute the PE checksum.

Usage:
    python patch.py manifest.json input.exe output.exe

Rules:
  * Offsets in the manifest are file offsets, never RVAs or VAs.
  * Every patch has an original byte string and a patch byte string.
  * The tool refuses an original mismatch, a pattern that is not unique,
    an overlap, or a patch that runs past the end of the file.
  * The PE checksum at e_lfanew + 4 + 20 + 0x40 is recomputed after the
    last patch. Do not list the checksum field as a patch.
  * expected_sha256 in the manifest is checked when present.

Exit codes: 0 pass, 1 verification failure, 2 usage or input error.
"""

import argparse
import hashlib
import json
import struct
import sys


def hex_bytes(text):
    return bytes.fromhex(text.replace(" ", ""))


def parse_pattern(text):
    data = []
    mask = []
    for token in text.split():
        if token in ("??", "?"):
            data.append(0)
            mask.append(False)
        else:
            data.append(int(token, 16))
            mask.append(True)
    return bytes(data), mask


def find_pattern(data, pattern, mask):
    hits = []
    n = len(pattern)
    for i in range(0, len(data) - n + 1):
        for j in range(n):
            if mask[j] and data[i + j] != pattern[j]:
                break
        else:
            hits.append(i)
    return hits


def pe_checksum(data, checksum_offset):
    total = 0
    for i in range(0, len(data), 2):
        if checksum_offset <= i < checksum_offset + 4:
            continue
        word = data[i]
        if i + 1 < len(data):
            word |= data[i + 1] << 8
        total += word
        total = (total & 0xFFFF) + (total >> 16)
    total = (total & 0xFFFF) + (total >> 16)
    return (total + len(data)) & 0xFFFFFFFF


def checksum_field(data):
    e_lfanew = struct.unpack("<I", data[0x3C:0x40])[0]
    return e_lfanew + 4 + 20 + 0x40


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("manifest")
    ap.add_argument("input")
    ap.add_argument("output")
    args = ap.parse_args()

    if args.output == args.input:
        print("refusing to overwrite the input; write a separate output")
        return 2

    try:
        data = bytearray(open(args.input, "rb").read())
    except OSError as exc:
        print("cannot read %s: %s" % (args.input, exc))
        return 2

    try:
        manifest = json.load(open(args.manifest, encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        print("cannot read %s: %s" % (args.manifest, exc))
        return 2

    patches = manifest.get("patches", [])
    if not patches:
        print("manifest has no patches")
        return 2

    applied = []
    occupied = []
    for spec in patches:
        name = spec.get("name", "patch")
        try:
            patch = hex_bytes(spec["patch"])
        except KeyError:
            print("%s: missing patch bytes" % name)
            return 2

        if "offset" in spec:
            offset = int(str(spec["offset"]), 0)
            if offset < 0 or offset + len(patch) > len(data):
                print("%s: offset 0x%X runs past end of file" % (name, offset))
                return 1
            if "original" in spec:
                original = hex_bytes(spec["original"])
                got = bytes(data[offset : offset + len(original)])
                if got != original:
                    print("%s: original mismatch at 0x%X" % (name, offset))
                    print("  expected %s" % original.hex(" "))
                    print("  found    %s" % got.hex(" "))
                    return 1
        elif "pattern" in spec:
            pattern, mask = parse_pattern(spec["pattern"])
            hits = find_pattern(data, pattern, mask)
            if not hits:
                print("%s: pattern not found" % name)
                return 1
            if len(hits) != 1 and not spec.get("allow_multiple"):
                print("%s: pattern matched %d times, expected 1" % (name, len(hits)))
                return 1
            offset = hits[0]
            if "original" in spec:
                original = hex_bytes(spec["original"])
                got = bytes(data[offset : offset + len(original)])
                if got != original:
                    print("%s: matched bytes do not equal original" % name)
                    return 1
        else:
            print("%s: needs offset or pattern" % name)
            return 2

        end = offset + len(patch)
        for a, b in occupied:
            if offset < b and a < end:
                print("%s: overlaps another patch at 0x%X..0x%X" % (name, a, b))
                return 1
        data[offset:end] = patch
        occupied.append((offset, end))
        applied.append((name, offset, len(patch)))

    chk = checksum_field(data)
    value = pe_checksum(bytes(data), chk)
    data[chk : chk + 4] = struct.pack("<I", value)

    try:
        open(args.output, "wb").write(bytes(data))
    except OSError as exc:
        print("cannot write %s: %s" % (args.output, exc))
        return 2

    print("%-32s %-10s %s" % ("patch", "offset", "bytes"))
    for name, offset, length in applied:
        print("%-32s 0x%08X %d" % (name, offset, length))
    print("checksum 0x%08X at file 0x%X" % (value, chk))
    print(
        "input  sha256 %s"
        % hashlib.sha256(open(args.input, "rb").read()).hexdigest().upper()
    )
    out_hash = hashlib.sha256(bytes(data)).hexdigest().upper()
    print("output sha256 %s" % out_hash)

    expected = manifest.get("expected_sha256")
    if expected and expected.upper() != out_hash:
        print("FAIL expected SHA256 %s" % expected.upper())
        return 1
    print("PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
