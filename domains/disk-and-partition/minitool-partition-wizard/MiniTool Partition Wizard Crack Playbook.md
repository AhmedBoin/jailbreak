# MiniTool Partition Wizard License Patch Playbook

Target: MiniTool Partition Wizard, native x64 Qt build.
Scope: desktop application and WinPE bootable media.
Reference build: 13.9 (Pro Ultimate). The method generalizes to 14.x and 15.x.

This file contains everything needed to locate and patch the license checks in a new build, including the exact 13.9 addresses, the RTTI anchors, the edition map, the WinPE-specific checker, and the ISO rebuild procedure.

---

## 1. Target profile

- Main binary: `partitionwizard.exe` (small launcher)
- Main code: `partitionwizard.dll` (about 8.4 MB in 13.9, x64, native C++, Qt5, LTCG, no .NET, no packer)
- Install path example: `C:\Program Files\MiniTool Partition Wizard <version>\`
- License code is inside `partitionwizard.dll`.
- Two separate license checker classes exist:
  - `KWindowsLicenseChecker`: used by the normal desktop application.
  - `KWinPELicenseChecker`: used when the process runs inside WinPE.
- The manager `KLicenseManagerPrivate` chooses between them at construction time by calling `IsRunningAnyPE()`.
- Patching only the desktop checker unlocks the desktop app but does not unlock the bootable media. The PE shows:
  `Only registered version can be run in Windows PE environment.`
- To unlock both, patch both checkers.

Key class and RTTI names:

```
ILicenseChecker
ILicenseManager
KWindowsLicenseChecker
KWinPELicenseChecker
KLicenseManagerPrivate
```

MSVC RTTI strings present in the DLL (13.9):

```
.?AVILicenseChecker@@
.?AVKWindowsLicenseChecker@@
.?AVKWinPELicenseChecker@@
.?AVILicenseManager@@
.?AVKLicenseManagerPrivate@@
```

IDA names for the vtables (13.9):

```
??_7ILicenseChecker@@6B@            RVA 0x6BFE98
??_7KWinPELicenseChecker@@6B@       RVA 0x6BFEE0
??_7KWindowsLicenseChecker@@6B@     RVA 0x6BFF28
??_7ILicenseManager@@6B@            RVA 0x6BFF70
??_7KLicenseManagerPrivate@@6B@     RVA 0x6BFFD0
```

Image base for 13.9: `0x180000000`.

---

## 2. 13.9 exact patch data

DLL facts:

```
size            8,432,880 bytes
pristine SHA256 02ED32946FFA02F938107B9BFF233B1E063F38762A553BD209F698B4E07E650D
patched SHA256  8B4442B4F5816530AE6B3CBB842133FB246737AB57AF714F5267B59F55A093BA
machine         AMD64
image base      0x180000000
.text           VA 0x1000   raw 0x400   size 0x2CE315
.rdata          VA 0x2D0000 raw 0x2CE800
.data           VA 0x7A3000 raw 0x7A1400
.idata          VA 0x7CA000 raw 0x7C4E00
```

For 13.9 only, inside `.text`: `file offset = RVA - 0xC00`.

Four patch sites:

| Checker | Method | RVA | File offset 13.9 | Original first bytes | Patch |
|---|---|---|---:|---|---|
| Desktop | `IsRegistered` | `0x13E7A0` | `0x13DBA0` | `48 8B C4 55 41 54 41 55 41 56 41 57 48 8B EC` | `B0 01 C3` |
| Desktop | `GetLicenseType` | `0x1404F0` | `0x13F8F0` | `48 8B C4 55 41 54 41 55 41 56 41 57 48 8B EC` | `B8 08 00 00 00 C3` |
| WinPE | `IsRegistered` | `0x13D460` | `0x13C860` | `40 55 53 48 8D AC 24 A8 FD FF FF 48 81 EC 58 03` | `B0 01 C3` |
| WinPE | `GetLicenseType` | `0x13F190` | `0x13E590` | `40 55 53 57 48 8D AC 24 B0 FD FF FF 48 81 EC 50` | `B8 08 00 00 00 C3` |

Patch meanings:

```
B0 01 C3                 mov al,1 ; ret        IsRegistered -> true
B8 08 00 00 00 C3        mov eax,8 ; ret       GetLicenseType -> 8 (Pro Ultimate)
```

Alternative IsRegistered patch if a caller expects a 32-bit bool in EAX:

```
B8 01 00 00 00 C3        mov eax,1 ; ret
```

A 3-byte `B0 01 C3` is sufficient for the C++ `bool` return used here.

After applying all four patches, the DLL SHA256 must be:

```
8B4442B4F5816530AE6B3CBB842133FB246737AB57AF714F5267B59F55A093BA
```

This is the fastest self-test for 13.9: patch a pristine copy, hash it, compare.

---

## 3. How the license system works

### 3.1 Manager factory

`KLicenseManagerPrivate` constructor (13.9 RVA `0x139600`) does:

```cpp
a1[1] = 0;
*a1 = &KLicenseManagerPrivate::vftable;
if (IsRunningAnyPE()) {
    a1[1] = sub_180004A11();      // returns the static KWinPELicenseChecker
} else {
    a1[1] = &qword_1807AC310;     // static KWindowsLicenseChecker
}
```

13.9 objects:

```
KWinPELicenseChecker static object  0x1807AB5F0
KWindowsLicenseChecker static object 0x1807AC310
```

`sub_180004A11` is a thunk to `sub_180043C60`, which lazily constructs the PE checker with `sub_180139770`.

### 3.2 Interface layout

Both checkers implement `ILicenseChecker`. The vtable layout is:

```
+0x00  destructor
+0x08  IsRegistered() -> bool
+0x10  GetLicenseType() -> int
+0x18  other license info method
+0x20  other method
+0x28  other method
```

13.9 `KWindowsLicenseChecker` vtable at RVA `0x6BFF28`:

```
+0x00  RVA 0x3751
+0x08  RVA 0xA3E9   thunk -> VA 0x18013E7A0  (desktop IsRegistered)
+0x10  RVA 0x84F4   thunk -> VA 0x1801404F0  (desktop GetLicenseType)
+0x18  RVA 0x8404
+0x20  RVA 0x9DEA
+0x28  RVA 0xA86C
```

13.9 `KWinPELicenseChecker` vtable at RVA `0x6BFEE0`:

```
+0x00  RVA 0x7950
+0x08  RVA 0xA04C   thunk -> VA 0x18013D460  (PE IsRegistered)
+0x10  RVA 0x8ECC   thunk -> VA 0x18013F190  (PE GetLicenseType)
+0x18  RVA 0x2D92   -> 0x18013EBF0
+0x20  RVA 0x68B1   -> 0x18013CED0
+0x28  RVA 0x228E   -> 0x18013B160
```

The vtable slots are thunks of the form:

```
mov rcx, [rcx+8]
mov rax, [rcx]
jmp qword ptr [rax+8]     ; IsRegistered
```

or `jmp qword ptr [rax+0x10]` for `GetLicenseType`.

Patch the implementation functions, or patch the thunks if the implementation layout is unclear. The implementation RVAs above are the reliable targets.

### 3.3 What the functions return

`KWinPELicenseChecker::IsRegistered` (13.9 RVA `0x13D460`):

- Reads `this+32` as a flag.
- If the flag is zero, returns false.
- If the flag is set, compares the QString at `this+16` against a list of accepted hashes.
- The object is constructed with `this+32 = 0` and empty strings, so an unlicensed PE returns false.

`KWinPELicenseChecker::GetLicenseType` (13.9 RVA `0x13F190`):

- If `this+32 == 0`, returns `0xFFFFFFFF` (-1).
- Otherwise computes hashes and returns a known edition value.

`KWindowsLicenseChecker` follows the same interface, but its license data comes from the desktop installation rather than the PE media.

`KWinPELicenseChecker` constructor (13.9 RVA `0x139770`):

```cpp
*(void**)this = &KWinPELicenseChecker::vftable;
QString::QString(this + 8);
QString::QString(this + 16);
*(void**)(this + 24) = QListData::shared_null;
*(unsigned char*)(this + 32) = 0;
```

The boot media contains no license file that fills these fields. Patching the two methods is sufficient.

---

## 4. Finding the patch sites in a new version

### 4.1 Fast path with radare2

Radare2 parses MSVC RTTI and names the virtual methods. This is the quickest route.

```bat
radare2 -2 -q -A -e scr.color=0 -c "f~KWindowsLicenseChecker" "partitionwizard.dll"
radare2 -2 -q -A -e scr.color=0 -c "f~KWinPELicenseChecker" "partitionwizard.dll"
```

In 13.9 this printed:

```
method.KWinPELicenseChecker.virtual_8  0x18000a04c  jmp 0x18013d460
method.KWinPELicenseChecker.virtual_16 0x180008ecc  jmp 0x18013f190
```

For the desktop checker the equivalent flags are:

```
method.KWindowsLicenseChecker.virtual_8
method.KWindowsLicenseChecker.virtual_16
```

`virtual_8` is vtable offset 8, `IsRegistered`. `virtual_16` is vtable offset 0x10, `GetLicenseType`.

Follow a thunk:

```bat
radare2 -2 -q -A -e scr.color=0 -c "s 0x18000a04c; pd 3" "partitionwizard.dll"
```

The `jmp` target is the implementation. Decompile or disassemble it:

```bat
radare2 -2 -q -A -e scr.color=0 -c "s 0x18013d460; pdf" "partitionwizard.dll"
```

If the new build uses the same class names, this gives the four RVAs in under a minute.

If the flags are absent, use IDA or the RTTI strings directly.

### 4.2 Finding the RTTI strings without symbols

Search the binary for the type descriptor names:

```
.?AVKWindowsLicenseChecker@@
.?AVKWinPELicenseChecker@@
```

In 13.9:

```
.?AVKWinPELicenseChecker@@   RVA 0x7A9BB0
.?AVKWindowsLicenseChecker@@ RVA 0x7A9BE8
```

IDA will label the vtables `??_7...@@6B@` once RTTI is parsed. Radare2 will label the methods `method.<Class>.virtual_<offset>`.

### 4.3 IDA discovery script

Run IDA in headless mode with a script that prints the vtable slots and follows direct jumps:

```python
import idaapi, idc, ida_bytes, idautils, ida_hexrays, ida_funcs

idaapi.auto_wait()
ida_hexrays.init_hexrays_plugin()

def follow(ea, depth=0):
    line = idc.generate_disasm_line(ea, 0)
    print("  " * depth + hex(ea) + "  " + line)
    if idc.print_insn_mnem(ea) == "jmp":
        if idc.get_operand_type(ea, 0) == idc.o_near:
            return follow(idc.get_operand_value(ea, 0), depth + 1)
    return ea

for name in ("??_7KWindowsLicenseChecker@@6B@", "??_7KWinPELicenseChecker@@6B@"):
    vt = idc.get_name_ea_simple(name)
    print("\n" + name + "  " + hex(vt))
    for off in (8, 0x10):
        target = ida_bytes.get_qword(vt + off)
        print("slot " + hex(off) + " -> " + hex(target))
        impl = follow(target)
        print("impl " + hex(impl))
        try:
            print(ida_hexrays.decompile(impl))
        except Exception as e:
            print("decompile failed: " + str(e))
```

For a new build, read the printed implementation addresses and patch those.

### 4.4 Fallback anchors

If RTTI is stripped or the classes are renamed:

- Search for `Only registered version can be run in Windows PE environment.`
  In 13.9 this string is at RVA `0x68FA50`, referenced from `0x18003FC32`.
  The surrounding code checks the PE license before opening the main window.
- Search for `verconfig-v11-registered.txt` and `verconfig-v11-free.txt`.
  In 13.9: `0x68EC50` and `0x68EC30`.
- Search for `IsRegistered=%1 LicenseType=%2`.
  In 13.9: `0x6C0068`.
- Search for the edition name literals:
  `MiniTool Partition Wizard Pro Ultimate`, `Pro Deluxe`, `Pro Platinum`, `Technician`, `Server`, `Enterprise`, `Giveaway Edition`.
- Find the edition switch function. In 13.9 it is RVA `0x139ED0`, with a 17-entry jump table at `0x13A0EC`.
- Find `KLicenseManagerPrivate` and its constructor. In 13.9 RVA `0x139600`.
- Find `IsRunningAnyPE` and the static checker objects. In 13.9:
  `0x18023036E` (IsRunningAnyPE), `0x1807AB5F0` (PE checker), `0x1807AC310` (desktop checker).

### 4.5 Confirming the functions

`IsRegistered` should:

- Take `this` in RCX.
- Return a bool in AL.
- Reference a byte flag at `this+32` in the PE variant.
- Reference a QString at `this+16`.

`GetLicenseType` should:

- Take `this` in RCX.
- Return an int in EAX.
- Compare or switch on edition values.
- Reference the license data and edition strings.

Once confirmed, patch both methods in both classes.

---

## 5. Edition values

13.9 edition switch values, from the jump table at RVA `0x13A0EC`:

| Value | Edition |
|---:|---|
| `0x00` | Pro |
| `0x01` | Server |
| `0x02` | Enterprise |
| `0x03` | Free |
| `0x04` | Technician |
| `0x05` | Pro |
| `0x06` | Server |
| `0x07` | Enterprise |
| `0x08` | Pro Ultimate |
| `0x09` | Giveaway Edition |
| `0x0A` | Pro |
| `0x0B` | Pro Deluxe |
| `0x0C` | Pro |
| `0x0D` | Pro Platinum |
| `0x0E` | Server |
| `0x0F` | Enterprise |
| `0x10` | Technician |

For Pro Ultimate use `8`:

```
B8 08 00 00 00 C3
```

For Technician use `0x10`:

```
B8 10 00 00 00 C3
```

The edition name switch maps the value to the title bar string. `8` produces:

```
MiniTool Partition Wizard Pro Ultimate 13.9 - (with lifetime upgrade service)
```

---

## 6. Bootable media

The bootable ISO is a WinPE image with MiniTool injected.

13.9 layout:

```
ISO type            UDF
sources\boot.wim    Windows PE 10, build 26100, x64
Program Files\partitionwizard.dll   the same DLL, embedded
Program Files\Winpeshl.ini          launch script
Program Files\MTPELoader.exe        PE shell
Program Files\PETools\...           boot files
```

`Winpeshl.ini`:

```
[LaunchApps]
"X:\Program Files\MTPELoader.exe"
"%SYSTEMDRIVE%\Windows\System32\cmd.exe"
```

The PE reads `X:\Program Files\partitionwizard.dll`. The ISO builder copies the installed program folder, including the patched DLL and any `.orig_backup` files that are present. Remove backups before building if you do not want them in the media.

Important: the PE uses `KWinPELicenseChecker`, not `KWindowsLicenseChecker`. Patching only the desktop pair produces:

```
Only registered version can be run in Windows PE environment.
```

The ISO contains no license blob that satisfies the PE checker. `pas.cnf` is byte-identical to the installed copy, and no `verconfig-v11-registered.txt` is present. The two PE method patches are the fix.

### 6.1 Patch the installed DLL, then rebuild

1. Close `partitionwizard.exe`.
2. Patch all four RVAs in `C:\Program Files\MiniTool Partition Wizard <version>\partitionwizard.dll`.
3. Delete `partitionwizard.dll.orig_backup_*` and any crack/tool folders from the install directory.
4. Run the app's `Create Bootable Media` again.
5. The new `boot.wim` will contain the doubly patched DLL.

### 6.2 Patch an existing ISO directly

1. Extract `sources\boot.wim` from the ISO.
2. Mount it:

```bat
dism /Mount-Image /ImageFile:boot.wim /Index:1 /MountDir:<mount-dir>
```

3. Patch `<mount-dir>\Program Files\partitionwizard.dll` at the PE offsets:
   `0x13C860` and `0x13E590` for 13.9.
4. Unmount:

```bat
dism /Unmount-Image /MountDir:<mount-dir> /Commit
```

5. Rebuild the ISO with the app's `oscdimg.exe`:

```bat
oscdimg.exe -m -o -u2 -udfver102 -h ^
  -bootdata:2#p0,e,b<iso-root>\boot\etfsboot.com#pEF,e,b<iso-root>\PETools\amd64\boot\efisys.bin ^
  -lDVD_ROM <iso-root> <output.iso>
```

`MTMediaBuilder.exe` contains the exact prefix:

```
 -m -o -u2 -udfver102 -bootdata:2#p0,e,b
```

It uses the amd64 `PETools\boot\efisys.bin` for the UEFI entry, not the root `boot\efisys.bin`. The two files differ. Use the PETools one.

13.9 El Torito catalog, for comparison:

```
validation entry: platform 0x00, "Microsoft Corporation", checksum 0x494C
entry 0: BIOS, media 0x00, 8 sectors, RBA 401  (etfsboot.com)
entry 1: section header, platform 0xEF
entry 2: EFI, media 0x00, 1 sector, RBA 403    (efisys.bin FAT image)
```

The original and rebuilt ISOs had identical catalog structures.

---

## 7. Updates

The app installs a scheduled task:

```
\MiniToolPartitionWizard
C:\Program Files\MiniTool Partition Wizard <version>\updatechecker.exe /fromtask
```

It runs at logon. Update endpoints found in the DLL:

```
http://tracking.minitool.com/pw13/update-checker.html
http://tracking.minitool.com/pw13/update-download.html
http://tracking.minitool.com/pw13/update-noticed.html
http://www.PartitionWizard.com/checking-update/
```

A MiniTool update installs a new `partitionwizard.dll` and overwrites the patches. The existing bootable ISO keeps its own old DLL and remains patched, but it does not get the new version.

To freeze the current version:

```bat
schtasks /Change /TN "\MiniToolPartitionWizard" /Disable
ren "C:\Program Files\MiniTool Partition Wizard <version>\updatechecker.exe" updatechecker.exe.off
```

Optionally block `tracking.minitool.com` and `www.partitionwizard.com` in the hosts file.

To update and keep the patch:

1. Save the current patched DLL and ISO.
2. Install the update.
3. Re-run the discovery steps on the new DLL.
4. Patch both checkers.
5. Rebuild the boot ISO.
6. Verify.

The old patched DLL should not be restored over a new version. The EXE, config, and license manager may have changed.

---

## 8. Verification

Desktop:

- Title bar shows `MiniTool Partition Wizard Pro Ultimate <version> - (with lifetime upgrade service)`.
- The `Register` button is gone.
- Pro-gated dialogs open instead of the upgrade prompt.

WinPE:

- Boot the ISO.
- The error `Only registered version can be run in Windows PE environment.` must not appear.
- The PE title bar should show the Pro Ultimate edition.
- The PE Loader may show an "already launched" message; the app window can be behind it. Use Alt+Tab.

Frida check for 13.9 (desktop):

```js
const base = Module.getBaseAddress("partitionwizard.dll");
Interceptor.attach(base.add(0x13E7A0), {
  onLeave(ret) { console.log("Desktop IsRegistered", ret.value); }
});
Interceptor.attach(base.add(0x1404F0), {
  onLeave(ret) { console.log("Desktop GetLicenseType", ret.value); }
});
```

For PE, the offsets are `0x13D460` and `0x13F190`.

Fast self-test for 13.9:

1. Copy the pristine DLL.
2. Apply the four patches.
3. SHA256 must equal `8B4442B4F5816530AE6B3CBB842133FB246737AB57AF714F5267B59F55A093BA`.

---

## 9. Rollback

Keep a pristine DLL outside the install directory:

```
<backup-dir>\partitionwizard.dll.orig
```

13.9 pristine SHA256:

```
02ED32946FFA02F938107B9BFF233B1E063F38762A553BD209F698B4E07E650D
```

Restore by replacing `partitionwizard.dll` with that file while the app is closed. Do not leave the pristine backup inside the install directory if you plan to rebuild the boot media, because the builder copies it into `boot.wim`.

---

## 10. Reference addresses and strings, 13.9

Addresses below are RVAs unless they start with 0x180, which are VAs.

Classes and factories:

```
KWindowsLicenseChecker vtable        0x6BFF28
KWinPELicenseChecker vtable          0x6BFEE0
KLicenseManagerPrivate vtable        0x6BFFD0
KLicenseManagerPrivate ctor          0x139600
KWinPELicenseChecker ctor            0x139770
KWindowsLicenseChecker ctor          0x1397C0
PE checker factory thunk             0x180004A11 -> 0x180043C60
PE checker static object             0x1807AB5F0
Desktop checker static object        0x1807AC310
IsRunningAnyPE                       0x18023036E
Edition switch function              0x139ED0
Edition switch jump table            0x13A0EC
```

Methods:

```
Desktop IsRegistered                 0x13E7A0
Desktop GetLicenseType               0x1404F0
WinPE IsRegistered                   0x13D460
WinPE GetLicenseType                 0x13F190
```

Strings:

```
Only registered version can be run in Windows PE environment.   0x68FA50
xref of that string                                              0x18003FC32
verconfig-v11-free.txt                                          0x68EC30
verconfig-v11-registered.txt                                    0x68EC50
IsRegistered=%1 LicenseType=%2                                  0x6C0068
.?AVKWinPELicenseChecker@@                                      0x7A9BB0
.?AVKWindowsLicenseChecker@@                                    0x7A9BE8
```

RTTI/vtable section is around RVA `0x6BFE98` to `0x6BFFD0`.

---

## 11. Generic patch script

Use this after discovering the four RVAs in a new build. Back up the DLL first. Close the app.

```python
import pefile

PATH = r"C:\Program Files\MiniTool Partition Wizard <version>\partitionwizard.dll"

# Replace these with the RVAs found in the new build.
PATCHES = [
    (0x13E7A0, "B0 01 C3"),              # desktop IsRegistered
    (0x1404F0, "B8 08 00 00 00 C3"),     # desktop GetLicenseType
    (0x13D460, "B0 01 C3"),              # WinPE IsRegistered
    (0x13F190, "B8 08 00 00 00 C3"),     # WinPE GetLicenseType
]

pe = pefile.PE(PATH, fast_load=True)
data = bytearray(open(PATH, "rb").read())

for rva, hexbytes in PATCHES:
    off = pe.get_offset_from_rva(rva)
    patch = bytes.fromhex(hexbytes)
    print("0x%X -> file 0x%X : %s" % (rva, off, patch.hex(" ")))
    data[off:off + len(patch)] = patch

open(PATH, "wb").write(data)
print("written")
```

For a new version, replace the four RVAs. Do not reuse the 13.9 RVAs blindly.

If the target functions are thunks, patch the thunk target instead. If the thunk is `jmp qword ptr [rax+8]`, patching the thunk itself with `B0 01 C3` also works for `IsRegistered` because it ignores `this` and returns a constant. Patching the implementation is cleaner.

---

## 12. Pitfalls

- Patching only `KWindowsLicenseChecker` unlocks the desktop app but not WinPE. The PE error is the symptom.
- Do not patch the `KLicenseManagerPrivate` wrapper at `0x6BFFD0` unless you understand both inner objects. Patch the inner checker implementations.
- The vtable slots may point to thunks. Follow the `jmp` before deciding what to patch.
- `GetLicenseType` must return a valid edition value. `8` is Pro Ultimate in 13.9. Use `0x10` for Technician.
- `IsRegistered` returns `bool` in AL. `B0 01 C3` is enough. If a caller reads EAX, use `B8 01 00 00 00 C3`.
- The PE checker is constructed with `this+32 = 0`. There is no license file in `boot.wim` that sets it. Do not waste time looking for one.
- The boot media builder copies `partitionwizard.dll.orig_backup_*` into `Program Files` inside `boot.wim` if it is present. Remove backups from the install directory before rebuilding.
- The bootable ISO is standalone. Updating the desktop app does not update the ISO.
- The app is not signature-checking its own DLL at runtime, but a future version may add integrity checks. If the patched app crashes at startup, check for a hash or signature check before the license manager.
- A 14.x or 15.x build may rename the classes or move the license code to another DLL. Search all DLLs in the install directory for `KWinPELicenseChecker` and `Only registered version can be run in Windows PE environment.`

---

## 13. Fast checklist for a new version

1. Locate `partitionwizard.dll` in the new install directory.
2. Record size and SHA256.
3. Run:
   `radare2 -2 -q -A -e scr.color=0 -c "f~LicenseChecker" partitionwizard.dll`
4. Note `method.KWindowsLicenseChecker.virtual_8`, `.virtual_16`, and the `KWinPE` equivalents.
5. Follow each `jmp` to the implementation.
6. Confirm `IsRegistered` returns bool and `GetLicenseType` returns an int.
7. Patch both methods in both classes:
   - `IsRegistered` -> `B0 01 C3`
   - `GetLicenseType` -> `B8 08 00 00 00 C3`
8. Launch the desktop app, verify the title bar and no Register button.
9. Rebuild the bootable media.
10. Boot the PE and verify there is no registration error.

---

## 14. Companion 13.9 procedure

This repository does not ship a standalone patcher. Use the four offsets above with a local hex editor or a local script. Any local tooling should check the 13.9 size and bytes and refuse unknown builds. For a new version, use the discovery workflow above and patch the new RVAs.

---

## 15. One-line summary

MiniTool Partition Wizard uses two byte-patchable license getters per checker: `IsRegistered` returns a bool, `GetLicenseType` returns an edition enum. Patch `IsRegistered` to return true and `GetLicenseType` to return 8 in both `KWindowsLicenseChecker` and `KWinPELicenseChecker`, then rebuild the WinPE ISO so the embedded DLL carries the same four patches.
