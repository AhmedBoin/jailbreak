import sys, struct, pefile

path = sys.argv[1]
pe = pefile.PE(path)
data = open(path, "rb").read()
IB = pe.OPTIONAL_HEADER.ImageBase

for a in sys.argv[2:]:
    off = int(a, 0)
    rva = pe.get_rva_from_offset(off)
    va = rva + IB
    pat = struct.pack("<I", va)
    hits = []
    start = 0
    while True:
        i = data.find(pat, start)
        if i < 0:
            break
        hits.append(i)
        start = i + 1
    print("str file 0x%X rva 0x%X va 0x%X : %d refs" % (off, rva, va, len(hits)))
    for i in hits:
        print(
            "   ref file 0x%-7X rva 0x%-7X ctx %s"
            % (i, pe.get_rva_from_offset(i), data[max(0, i - 12) : i + 4].hex(" "))
        )
