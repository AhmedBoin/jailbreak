import sys, struct, pefile

path = sys.argv[1]
pe = pefile.PE(path, fast_load=False)


def walk(entries, path_parts):
    for e in entries:
        if hasattr(e, "directory"):
            name = e.name
            if name is None:
                name = e.id
            walk(e.directory.entries, path_parts + [str(name)])
        else:
            d = e.data.struct
            off = pe.get_offset_from_rva(d.OffsetToData)
            print(
                "/".join(path_parts)
                + "  rva=0x%X file=0x%X size=%d" % (d.OffsetToData, off, d.Size)
            )


for entry in pe.DIRECTORY_ENTRY_RESOURCE.entries:
    tname = entry.name.string.decode(errors="replace") if entry.name else entry.id
    walk(entry.directory.entries, ["type=%s" % tname])
