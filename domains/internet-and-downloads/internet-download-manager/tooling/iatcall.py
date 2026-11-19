import sys, struct, pefile, capstone

path = sys.argv[1]
pe = pefile.PE(path)
data = open(path, "rb").read()
IB = pe.OPTIONAL_HEADER.ImageBase
text = [s for s in pe.sections if s.Name.rstrip(b"\0") == b".text"][0]
r0 = text.PointerToRawData
r1 = r0 + text.SizeOfRawData

iat = {}
for entry in pe.DIRECTORY_ENTRY_IMPORT:
    for imp in entry.imports:
        if imp.name:
            iat[imp.address - IB] = imp.name.decode(errors="replace")

md = capstone.Cs(capstone.CS_ARCH_X86, capstone.CS_MODE_32)

want = sys.argv[2:] or ["FindResourceA", "FindResourceExA"]
for i in range(r0, r1 - 6):
    if data[i] != 0xFF or data[i + 1] != 0x15:
        continue
    slot = struct.unpack_from("<I", data, i + 2)[0] - IB
    nm = iat.get(slot)
    if nm in want:
        rva = pe.get_rva_from_offset(i)
        print("%s at file 0x%X rva 0x%X" % (nm, i, rva))
        buf = data[i - 0x30 : i + 8]
        for ins in md.disasm(buf, IB + rva - 0x30):
            print("   0x%X %s %s" % (ins.address - IB, ins.mnemonic, ins.op_str))
        print()
