import sys, struct, pefile

path = sys.argv[1]
pe = pefile.PE(path)
data = open(path, "rb").read()


def dlg_title(off, size):
    d = data[off : off + size]

    def sz(p):
        if p + 2 > len(d):
            return "", p
        w = struct.unpack_from("<H", d, p)[0]
        if w == 0:
            return "", p + 2
        if w == 0xFFFF:
            return "#%d" % struct.unpack_from("<H", d, p + 2)[0], p + 4
        e = p
        while e + 1 < len(d) and (d[e] | (d[e + 1] << 8)) != 0:
            e += 2
        return d[p:e].decode("utf-16-le", errors="replace"), e + 2

    ver = struct.unpack_from("<H", d, 0)[0]
    sig = struct.unpack_from("<H", d, 2)[0] if len(d) >= 4 else 0
    p = 26 if (ver == 1 and sig == 0xFFFF) else 18
    menu, p = sz(p)
    cls, p = sz(p)
    title, p = sz(p)
    return title


def walk(entries, parts):
    for e in entries:
        if hasattr(e, "directory"):
            name = e.name.string.decode(errors="replace") if e.name else e.id
            walk(e.directory.entries, parts + [str(name)])
        else:
            if parts[0] != "5":
                continue
            d = e.data.struct
            off = pe.get_offset_from_rva(d.OffsetToData)
            try:
                t = dlg_title(off, d.Size)
            except Exception as exc:
                t = "ERR %s" % exc
            print(
                "dialog id %s file 0x%X size %d title=%r" % (parts[1], off, d.Size, t)
            )


for entry in pe.DIRECTORY_ENTRY_RESOURCE.entries:
    tname = entry.name.string.decode(errors="replace") if entry.name else entry.id
    walk(entry.directory.entries, [str(tname)])
