import sys, pefile, capstone

path = sys.argv[1]
off = int(sys.argv[2], 0)
back = int(sys.argv[3], 0) if len(sys.argv) > 3 else 0x80
fwd = int(sys.argv[4], 0) if len(sys.argv) > 4 else 0x120

pe = pefile.PE(path, fast_load=False)
data = open(path, "rb").read()
image_base = pe.OPTIONAL_HEADER.ImageBase

iat = {}
for entry in pe.DIRECTORY_ENTRY_IMPORT:
    for imp in entry.imports:
        if imp.name:
            iat[imp.address - image_base] = imp.name.decode(errors="replace")
        else:
            iat[imp.address - image_base] = "ord_%d" % imp.ordinal

sections = []
for s in pe.sections:
    sections.append(
        (
            s.VirtualAddress,
            s.VirtualAddress + max(s.Misc_VirtualSize, s.SizeOfRawData),
            s.Name.rstrip(b"\0").decode(),
        )
    )


def sec_of(rva):
    for a, b, n in sections:
        if a <= rva < b:
            return n
    return "?"


start_off = max(0, off - back)
rva = pe.get_rva_from_offset(start_off)

md = capstone.Cs(capstone.CS_ARCH_X86, capstone.CS_MODE_32)
md.detail = True

buf = data[start_off : off + fwd]
for ins in md.disasm(buf, image_base + rva):
    foff = pe.get_offset_from_rva(ins.address - image_base)
    text = "%s %s" % (ins.mnemonic, ins.op_str)
    note = ""
    if ins.mnemonic in ("call", "jmp") and "[" in ins.op_str:
        import re

        m = re.search(r"0x([0-9a-f]+)", ins.op_str)
        if m:
            target = int(m.group(1), 16) - image_base
            if target in iat:
                note = "   ; %s" % iat[target]
    if ins.mnemonic in ("call", "jmp") and ins.op_str.startswith("0x"):
        t = int(ins.op_str, 16) - image_base
        note = "   ; rva 0x%X [%s]" % (t, sec_of(t))
    print(
        "0x%X (rva 0x%X)  %-24s %s%s"
        % (foff, ins.address - image_base, ins.bytes.hex(" "), text, note)
    )
