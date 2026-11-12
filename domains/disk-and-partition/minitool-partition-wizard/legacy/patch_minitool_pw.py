#!/usr/bin/env python3
"""
MiniTool Partition Wizard 13.9 edition patch.

Turns the Free build into Pro Ultimate (or another edition) by patching two
methods of the license manager inside partitionwizard.dll.

Usage, from an elevated prompt:

    python patch_minitool_pw.py --check
    python patch_minitool_pw.py --apply
    python patch_minitool_pw.py --apply --edition technician
    python patch_minitool_pw.py --restore

Stdlib only. No pefile, no capstone, no third party packages.
"""

import argparse
import glob
import hashlib
import os
import shutil
import struct
import sys
import time

# ---------------------------------------------------------------- build data

# Original partitionwizard.dll 13.9, 8432880 bytes.
ORIGINAL_SHA256 = "02ed32946ffa02f938107b9bff233b1e063f38762a553bd209f698b4e07e650d"
ORIGINAL_SIZE = 8432880

# RVA of the two implementation methods behind ILicenseManager.
RVA_IS_REGISTERED = 0x13E7A0
RVA_GET_TYPE = 0x1404F0

# First bytes at those RVAs in the untouched build.
ORIG_IS_REG = bytes.fromhex("488bc4")
ORIG_GET_TYPE = bytes.fromhex("488bc4554154")

# Replacement bytes.
PATCH_IS_REG = bytes.fromhex("b001c3")  # mov al,1 ; ret
PATCH_IS_REG_ALT = bytes.fromhex("b801000000c3")  # mov eax,1 ; ret

# GetLicenseType stub is built per edition: b8 <value> 00 00 00 c3.
GET_TYPE_TAIL = bytes.fromhex("000000c3")

# GetLicenseType values to edition names, decoded from the switch table at
# RVA 0x13a0ec inside the edition-name function at RVA 0x139ed0.
EDITIONS = {
    "free": 3,
    "pro": 0,
    "prodeluxe": 0x0B,
    "proplatinum": 0x0D,
    "proultimate": 8,
    "giveaway": 9,
    "server": 1,
    "enterprise": 2,
    "technician": 0x10,
}

DEFAULT_EDITION = "proultimate"


# ---------------------------------------------------------------- PE helpers


def find_section(data, rva):
    """Return (name, virtual_address, raw_pointer, raw_size, span) for an RVA."""
    if data[:2] != b"MZ":
        raise ValueError("not a PE file (no MZ header)")
    e_lfanew = struct.unpack_from("<I", data, 0x3C)[0]
    if data[e_lfanew : e_lfanew + 4] != b"PE\0\0":
        raise ValueError("not a PE file (no PE signature)")

    coff = e_lfanew + 4
    machine, num_sec = struct.unpack_from("<HH", data, coff)
    if machine != 0x8664:
        raise ValueError("not an x64 image (machine 0x%04x)" % machine)
    size_opt = struct.unpack_from("<H", data, coff + 16)[0]

    sec_table = coff + 20 + size_opt
    for i in range(num_sec):
        off = sec_table + i * 40
        name = data[off : off + 8].rstrip(b"\0").decode("ascii", "replace")
        vsize, va, rawsize, rawptr = struct.unpack_from("<IIII", data, off + 8)
        span = max(vsize, rawsize)
        if va <= rva < va + span:
            return name, va, rawptr, rawsize, span
    raise ValueError("RVA 0x%x is not inside any section" % rva)


def rva_to_offset(data, rva):
    _name, va, rawptr, _rawsize, _span = find_section(data, rva)
    return rawptr + (rva - va)


def read_at(data, rva, size):
    off = rva_to_offset(data, rva)
    return bytes(data[off : off + size])


def write_at(fh, data, rva, blob):
    off = rva_to_offset(data, rva)
    fh.seek(off)
    fh.write(blob)
    fh.flush()
    os.fsync(fh.fileno())


# ---------------------------------------------------------------- detection


def state_is_registered(data):
    """Return ('original'|'patched'|'unknown', bytes)."""
    have = read_at(data, RVA_IS_REGISTERED, 6)
    if have[:3] == PATCH_IS_REG or have[:6] == PATCH_IS_REG_ALT:
        return "patched", have
    if have[:3] == ORIG_IS_REG:
        return "original", have
    return "unknown", have


def state_get_type(data):
    """Return ('original'|'patched'|'unknown', value, bytes)."""
    have = read_at(data, RVA_GET_TYPE, 6)
    if have[:6] == ORIG_GET_TYPE:
        return "original", None, have
    if (
        len(have) == 6
        and have[0] == 0xB8
        and have[2:6] == GET_TYPE_TAIL
        and have[1] in EDITIONS.values()
    ):
        return "patched", have[1], have
    return "unknown", None, have


def is_reference(data, st_reg, st_type):
    if (
        len(data) == ORIGINAL_SIZE
        and hashlib.sha256(data).hexdigest() == ORIGINAL_SHA256
    ):
        return True
    # A previously patched copy of the same build is still a valid target.
    return (
        len(data) == ORIGINAL_SIZE
        and st_reg in ("original", "patched")
        and st_type in ("original", "patched")
    )


# ---------------------------------------------------------------- locate


def candidate_dlls():
    roots = [
        os.environ.get("ProgramFiles", r"C:\Program Files"),
        os.environ.get("ProgramFiles(x86)", r"C:\Program Files (x86)"),
    ]
    found = []
    for root in roots:
        pattern = os.path.join(
            root, "MiniTool Partition Wizard*", "partitionwizard.dll"
        )
        found.extend(sorted(glob.glob(pattern)))
    return found


def pick_dll(explicit):
    if explicit:
        if not os.path.isfile(explicit):
            sys.exit("No such file: %s" % explicit)
        return os.path.abspath(explicit)
    found = candidate_dlls()
    if not found:
        sys.exit("partitionwizard.dll not found. Pass --dll PATH.")
    if len(found) > 1:
        print("Several installs found:")
        for item in found:
            print("  " + item)
        print("Pass --dll PATH to choose one.")
        sys.exit(2)
    return found[0]


# ---------------------------------------------------------------- actions


def check(path):
    with open(path, "rb") as f:
        data = f.read()

    st_reg, bytes_reg = state_is_registered(data)
    st_type, value, bytes_type = state_get_type(data)

    print("file   : %s" % path)
    print("size   : %d bytes" % len(data))
    print("sha256 : %s" % hashlib.sha256(data).hexdigest())
    print(
        "build  : %s"
        % (
            "reference 13.9"
            if is_reference(data, st_reg, st_type)
            else "not the reference build, offsets may differ"
        )
    )
    print(
        "IsRegistered   (0x%x): %-8s bytes %s"
        % (RVA_IS_REGISTERED, st_reg, bytes_reg[:6].hex())
    )
    print(
        "GetLicenseType (0x%x): %-8s bytes %s"
        % (RVA_GET_TYPE, st_type, bytes_type.hex())
    )
    if st_type == "patched":
        names = [k for k, v in EDITIONS.items() if v == value]
        print("edition: %s (value %d)" % (names[0] if names else "unknown", value))
    return 0


def apply(path, edition, force):
    with open(path, "rb") as f:
        data = f.read()

    value = EDITIONS[edition]
    patch_type = bytes([0xB8, value]) + GET_TYPE_TAIL

    st_reg, have_reg = state_is_registered(data)
    st_type, current_value, have_type = state_get_type(data)

    if st_reg == "patched" and st_type == "patched" and current_value == value:
        print("Already patched to %s (value %d). Nothing to do." % (edition, value))
        return 0

    if not is_reference(data, st_reg, st_type) and not force:
        print("Refusing: this is not the reference 13.9 build.")
        print("Run with --force only after re-deriving the offsets for your version.")
        return 3

    if st_reg == "unknown" or st_type == "unknown":
        print("Unexpected bytes at a target RVA, refusing to write.")
        print("  IsRegistered   0x%x: %s" % (RVA_IS_REGISTERED, have_reg.hex()))
        print("  GetLicenseType 0x%x: %s" % (RVA_GET_TYPE, have_type.hex()))
        return 4

    backup = path + ".orig_backup_" + time.strftime("%Y%m%d_%H%M%S")
    shutil.copy2(path, backup)

    try:
        with open(path, "r+b") as f:
            if st_reg != "patched":
                write_at(f, data, RVA_IS_REGISTERED, PATCH_IS_REG)
            if st_type != "patched" or current_value != value:
                write_at(f, data, RVA_GET_TYPE, patch_type)
    except PermissionError:
        print(
            "Write denied. Close the app and run this script from an elevated prompt."
        )
        return 5
    except OSError as exc:
        print("Write failed: %s" % exc)
        print("Close MiniTool Partition Wizard and retry, or run elevated.")
        return 5

    with open(path, "rb") as f:
        after = f.read()
    ok_reg = state_is_registered(after)[0] == "patched"
    ok_type = state_get_type(after)[1] == value
    print("backup: %s" % backup)
    print("IsRegistered   -> %s" % ("OK" if ok_reg else "FAIL"))
    print(
        "GetLicenseType -> %s (value %d, %s)"
        % ("OK" if ok_type else "FAIL", value, edition)
    )
    return 0 if (ok_reg and ok_type) else 6


def restore(path):
    folder = os.path.dirname(path)
    base = os.path.basename(path)
    backups = []
    for suffix in (".orig_backup_*", ".bak_*", ".bak2_*"):
        backups.extend(glob.glob(os.path.join(folder, base + suffix)))
    if not backups:
        print("No backup found next to %s" % path)
        return 2

    def digest_of(candidate):
        try:
            with open(candidate, "rb") as handle:
                return hashlib.sha256(handle.read()).hexdigest()
        except OSError:
            return ""

    pristine = [b for b in backups if digest_of(b) == ORIGINAL_SHA256]
    if pristine:
        latest = max(pristine, key=os.path.getmtime)
    else:
        latest = max(backups, key=os.path.getmtime)
        print("warning: no pristine original backup found, using newest backup")
    print("restoring from %s" % latest)
    try:
        with open(latest, "rb") as f:
            data = f.read()
        target = path + ".restore_tmp"
        with open(target, "wb") as f:
            f.write(data)
        os.replace(target, path)
    except PermissionError:
        print("Write denied. Close the app and run elevated.")
        return 5
    except OSError as exc:
        print("Restore failed: %s" % exc)
        return 5

    with open(path, "rb") as f:
        digest = hashlib.sha256(f.read()).hexdigest()
    print("restored, sha256 = %s" % digest)
    print("matches reference original: %s" % (digest == ORIGINAL_SHA256))
    return 0


def main():
    ap = argparse.ArgumentParser(
        description="MiniTool Partition Wizard 13.9 edition patch"
    )
    group = ap.add_mutually_exclusive_group(required=True)
    group.add_argument(
        "--check", action="store_true", help="show build and patch state"
    )
    group.add_argument("--apply", action="store_true", help="write the patch")
    group.add_argument(
        "--restore", action="store_true", help="restore the newest backup"
    )
    ap.add_argument("--edition", default=DEFAULT_EDITION, choices=sorted(EDITIONS))
    ap.add_argument("--dll", default=None, help="explicit path to partitionwizard.dll")
    ap.add_argument("--force", action="store_true", help="allow unknown builds")
    args = ap.parse_args()

    path = pick_dll(args.dll)

    if args.check:
        return check(path)
    if args.restore:
        return restore(path)
    return apply(path, args.edition, args.force)


if __name__ == "__main__":
    sys.exit(main())
