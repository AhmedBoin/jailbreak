# UltraISO Premium 9.7.6.3829: trial to retail by four byte-level edits

Target: UltraISO Premium 9.7.6.3829 (EZB Systems), PE32 x86, shipped 2023-07-07.
Every address below is a reference for that build only. The patcher refuses any other size or hash, and any file whose sites are neither pristine nor already patched.

This document is written to be executed. Each phase ends with a gate; do not start the next phase until the gate passes. A build is done when the verification matrix in section 7 passes on a clean machine state, not when the trial window stops appearing.

The one rule that matters: **UltraISO decides "licensed" in more than one place.** The startup modal, the caption suffix, and 38 literal references to a licence flag are three different decisions reached from three different sites. Removing the modal alone leaves the caption and the flag consumers untouched, and the flag is cleared again inside the startup sequence even when it is forced (section 3.2).

---

## 1. Target profile

| Field | Value |
|---|---|
| Vendor | EZB Systems, Inc. (Authenticode subject: SHENZHEN YIBO DIGITAL SYSTEMS DEVELOPMENT CO., LTD.) |
| Product | UltraISO Premium, FileVersion 9.7.6.3829, ProductVersion V9.76 |
| Install path | `<install-dir>` (default `%ProgramFiles(x86)%\UltraISO`) |
| Main executable | `<install-dir>\UltraISO.exe`, 5543368 bytes |
| Other modules | `isoshell.dll`, `isoshl64.dll` (shell extension), `drivers\`, `lang\` |
| Format | PE32, Intel 386, GUI subsystem, image base `0x400000`, entry point `0x401644` |
| Toolchain | Delphi/VCL (window class names such as `TfrmStartup`, `TMainMenu` style menu handling) |
| Packer or protector | none; no UPX, no Themida, no virtualised code |
| Signature | Authenticode present on the shipped file; the patch invalidates it (see section 11) |
| Licence UI | startup modal `TfrmStartup` titled `Welcome` with "Register Now US$29.95"; caption suffix `(Trial Version)`; size limit on saving images |
| Update mechanism | none in the install folder; no in-app updater found |
| Secondary environment | the same executable builds bootable USB media and ISOs; there is no separate licence module for media |

## 2. Reference build

```text
file      UltraISO.exe
size      5543368
sha256    F89E9D336C6F49FBD847EA513A11BB1BFA80EA5FD1336E23CAD7D80370BAEA65   (shipped, pristine)
patched   31896FFD80D167F8B791F24C5EDAE0CAB083F2F56EE825A22D78C490B869192D   (27 bytes differ)
timestamp 0x64A8EF1C (2023-07-07)
entry     0x401644
sections  name      vaddr      vsize     rawptr    rawsize
          .text     0x001000   0x27E000  0x000600  0x27E000
          .data     0x27F000   0x6A8000  0x27E600  0x1B0800
          .tls      0x927000   0x001000  0x42EE00  0x000200
          .rdata    0x928000   0x001000  0x42F000  0x000200
          .idata    0x929000   0x004000  0x42F200  0x003800
          .edata    0x92D000   0x009000  0x432A00  0x008C00
          .rsrc     0x936000   0x0E2000  0x43B600  0x0E1E00
          .reloc    0xA18000   0x027000  0x51D400  0x026C00
```

Virtual address to file offset, always:

```text
offset = va - image_base - section.vaddr + section.rawptr
```

For `.text` that is `va - 0x400A00`; for `.data` it is `va - 0x4900`. Do not assume `va - 0x400000 - 0x600` for both, the two sections have different raw pointers.

A patcher must refuse any other build. The size guard alone is not enough, because different builds can share the size; the byte checks at all four sites are what make it safe.

## 3. Protection analysis

### 3.1 The startup decision block

This is the whole licence decision at startup, `.text` VA `0x403044` to `0x4030C3`:

```text
0x403045  e8 2a 7a 07 00         call 0x47aa74              ; licence loader
0x40304A  83 c4 08               add  esp, 8
0x40304D  a3 e0 be 6e 00         mov  [0x6ebee0], eax       ; store loader result
0x403052  8b 15 e0 be 6e 00      mov  edx, [0x6ebee0]       ; (site 1)
0x403058  85 d2                  test edx, edx
0x40305A  74 1d                  je   0x403079              ; zero -> clear and skip
0x40305C  8d 8d b0 fd ff ff      lea  ecx, [ebp-0x250]
0x403062  51                     push ecx
0x403063  8d 85 b0 fe ff ff      lea  eax, [ebp-0x150]
0x403069  50                     push eax
0x40306A  e8 9d e8 ff ff         call 0x40190c              ; (site 2) RSA validator
0x40306F  83 c4 08               add  esp, 8
0x403072  a3 e0 be 6e 00         mov  [0x6ebee0], eax       ; store validator result
0x403077  eb 08                  jmp  0x403081
0x403079  33 d2                  xor  edx, edx
0x40307B  89 15 e0 be 6e 00      mov  [0x6ebee0], edx       ; clear the flag
0x403081  ff 35 9c 37 6e 00      push dword [0x6e379c]
0x403087  e8 44 ee ff ff         call 0x401ed0              ; resource/window class lookup
0x40308C  59                     pop  ecx
0x40308D  85 c0                  test eax, eax
0x40308F  75 0a                  jne  0x40309b
0x403091  c7 05 ...              mov  [0x6e379c], 0x409      ; fallback resource id
0x40309B  8b 0d e8 da 7d 00      mov  ecx, [0x7ddae8]       ; first value
0x4030A1  a1 c0 f0 67 00         mov  eax, [0x67f0c0]       ; second value
0x4030A6  3b c8                  cmp  ecx, eax
0x4030A8  74 19                  je   0x4030c3              ; (site 3) equal -> skip nag
0x4030AA  8b 15 24 f5 82 00      mov  edx, [0x82f524]       ; nag block, 0x4030AA..0x4030BE
0x4030B0  8b 02                  mov  eax, [edx]
0x4030B2  8b 0d ec f1 82 00      mov  ecx, [0x82f1ec]
0x4030B8  8b 15 24 5b 76 00      mov  edx, [0x765b24]       ; registered window class TfrmStartup
0x4030BE  e8 95 bd 22 00         call 0x62ee58              ; show the modal
0x4030C3  a1 24 f5 82 00         mov  eax, [0x82f524]       ; continue startup
```

Notes that matter:

- `0x6ebee0` holds a licence-related flag. It has 38 literal 4-byte references in `.text`, and the count includes paths that look like the save-size limit. Section 3.2 shows that its value does not stay at 1 on any of the builds tested, so do not treat it as the master switch without measuring the feature that reads it.
- `0x47aa74` is the loader. It reads the registry pair, decodes the stored code (XOR with the 8-byte constant `93f7bfe8f2d09b81` rotated by the user name) and returns a boolean. It also fills the name and code globals the About box reads, so the loader must keep running. That is why site 2 replaces the validator call instead of the loader call.
- `0x40190c` is an RSA check. Modulus `0xA70F8F62AA6E97D1`, exponent `0x10001`, so a valid pair is mathematically constructible, but a valid pair alone does not flip the visible state on this build. Do not build the crack around the key; the shipped validator result is one input among several.
- The nag guard compares two globals that are not the licensed flag (`0x7ddae8` and `0x67f0c0`). They differ on an unlicensed install, which is what runs the `TfrmStartup` block. The class pointer at `0x765b24` is the modal form's class.
- The caption is composed at runtime. The trial suffix is the 15-byte literal at VA `0x6E7D55`, and it occurs exactly once in the file. The string `Premium Edition` already exists elsewhere at file offset `0x4C1CA8` (resource area), so the replacement reuses product wording rather than inventing it.

### 3.2 A second writer, and what the flag is not

VA `0x4241E7` re-evaluates the same global during the session:

```text
0x4241E7  8b 0d c0 f0 67 00      mov  ecx, [0x67f0c0]
0x4241ED  81 c1 22 06 00 00      add  ecx, 0x622            ; 1570
0x4241F3  a1 cc d0 6e 00         mov  eax, [0x6ed0cc]
0x4241F8  3b c8                  cmp  ecx, eax
0x4241FA  74 0a                  je   0x424206
0x4241FC  33 d2                  xor  edx, edx
0x4241FE  89 15 e0 be 6e 00      mov  [0x6ebee0], edx       ; clears it
0x424204  eb 0a                  jmp  0x424210
0x424206  c7 05 e0 be 6e 00 01 00 00 00   mov [0x6ebee0], 1
```

Measured on a live process (read at RVA `0x2EBEE0`, validated by reading the caption literal at RVA `0x2E7D55` in the same pass):

| Build | Value of `[0x6ebee0]` at 0.2 s | at 345 s | Windows |
|---|---|---|---|
| four site patch | 0 | 0 (sampled 23 times) | `UltraISO Premium Edition` |
| four site patch with the validator stub writing marker `0x12345678` | 0, marker never observed | - | `UltraISO Premium Edition` |
| five site patch (section 5) | 0 | 0 | `UltraISO Premium Edition` |

So the retail state does not come from this global staying at 1. The startup block does run, the store happens, and something clears the value inside the same startup sequence before the first 200 ms sample. The visible result is produced by site 3 (the nag branch) and site 4 (the caption), which is consistent with the single-change builds in section 3.3.

Do not build the crack around keeping `0x6ebee0` at 1. Treat the flag as a signal whose consumers matter only if a gated feature is observed failing, and verify that feature directly.

### 3.3 Measured attribution

One change per build, one clean start each, from the build-under-test session:

| Change alone | Result |
|---|---|
| `0x26A8` only | Welcome modal gone, caption still `(Trial Version)` |
| flag sites only | modal still appears |
| caption literal only | only the wording changes |

That is why the delivered patch is all four sites and not the one that removes the modal.

## 4. Patch sites

| # | VA | File offset | Original bytes | Patched bytes | Effect |
|---|---|---:|---|---|---|
| 1 | `0x403052` | `0x002652` | `8b 15 e0 be 6e 00` | `ba 01 00 00 00 90` | `mov edx,[0x6ebee0]` becomes `mov edx,1; nop`, so the loader result cannot send control to the clearing branch |
| 2 | `0x40306A` | `0x00266A` | `e8 9d e8 ff ff` | `b8 01 00 00 00` | the RSA validator call becomes `mov eax,1`, so the store at `0x403072` writes 1. The loader still runs and still fills the name and code globals |
| 3 | `0x4030A8` | `0x0026A8` | `74 19` | `eb 19` | `je 0x4030c3` becomes `jmp 0x4030c3`; the `TfrmStartup` block is always skipped |
| 4 | `0x6E7D55` | `0x2E7355` | `28 54 72 69 61 6c 20 56 65 72 73 69 6f 6e 29` | `50 72 65 6d 69 75 6d 20 45 64 69 74 69 6f 6e` | `(Trial Version)` becomes `Premium Edition`, same 15 bytes, no shift |

27 bytes differ in total. Every patch keeps instruction or literal length identical, so no relocation, section size, or virtual address changes, and no other code moves.

Why each site is safe to change in place:

- Site 1 and site 2 are five and six bytes, replaced by five and five byte sequences plus a padding `nop` or a shorter encoding. No branch target moves because nothing after them shifts.
- Site 3 changes a conditional jump into an unconditional one of the same size. The fall-through path (`0x4030AA`) becomes dead code that stays in the file.
- Site 4 is a byte-for-byte literal substitution of equal length inside `.data`.

## 5. Dead ends, recorded so nobody repeats them

| Attempt | Result |
|---|---|
| Only site 3 (`0x26A8`) | modal gone, caption still `(Trial Version)` |
| Only the flag sites | modal still appears |
| Only site 4 | only the wording changes |
| Adding a fifth site at `0x4241FA` (`74 0a` to `eb 0a`) to pin the re-evaluation branch | flag still reads 0, behaviour unchanged, output hash `194561E6C06AC87484CC81151BED7B13A23BD99D8FBBD7665C88941858FB3632`. Not part of the patch |
| Patching the validator stub to write a marker (`0x266A` to `b8 78 56 34 12`) | marker never observed in the live process, so the value is cleared within the startup sequence |
| UltraISO command-line image build (`-in` folder, `-out` iso) | no command-line parser in this build; the app wrote a 43 KB empty image and exited. Not a usable test path. Drive the GUI instead |

Keeping the flag at 1 by patch is not worth chasing until a gated feature is observed failing. The cap in section 11 is the only candidate worth a test.

## 6. Reproduce

### 6.1 With the bundled patcher

```text
powershell -NoProfile -ExecutionPolicy Bypass -File patcher\build.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File patcher\dist\patch-ultraiso.ps1 -Mode Check
powershell -NoProfile -ExecutionPolicy Bypass -File patcher\dist\patch-ultraiso.ps1 -Mode Apply
```

`-Target` and `-BackupDir` point the patcher at a copy and at a backup folder outside the install directory, which is how to test without touching the installed file:

```text
powershell -NoProfile -ExecutionPolicy Bypass -File patcher\dist\patch-ultraiso.ps1 `
  -Mode Apply -Target <work-dir>\UltraISO.exe -BackupDir <work-dir>\backup
```

Gate: `Apply` prints the patched SHA256 and `match : True`, then `state : patched`.

### 6.2 By hand

Read the file, check the four original byte sequences, write the four replacements, then hash:

```text
python - <<'PY'
import hashlib
p = r"<work-dir>\UltraISO.exe"
d = bytearray(open(p, "rb").read())
assert len(d) == 5543368
sites = [
    (0x2652, bytes.fromhex("8b15e0be6e00"), bytes.fromhex("ba0100000090")),
    (0x266A, bytes.fromhex("e89de8ffff"),   bytes.fromhex("b801000000")),
    (0x26A8, bytes.fromhex("7419"),         bytes.fromhex("eb19")),
    (0x2E7355, b"(Trial Version)",          b"Premium Edition"),
]
for off, old, new in sites:
    assert d[off:off+len(old)] == old, (hex(off), d[off:off+len(old)].hex())
    d[off:off+len(new)] = new
open(p, "wb").write(d)
print(hashlib.sha256(d).hexdigest().upper())
PY
```

Gate: the printed hash is `31896FFD80D167F8B791F24C5EDAE0CAB083F2F56EE825A22D78C490B869192D`. Two independent routes producing the same hash is the check that matters; a patcher that prints "done" and a matching hash from its own table proves nothing.

### 6.3 Install and start

```text
copy <install-dir>\UltraISO.exe <backup-dir>\UltraISO.exe.orig
copy <work-dir>\UltraISO.exe <install-dir>\UltraISO.exe     (needs elevation)
```

Close every UltraISO process first. Then launch and read the window titles.

## 7. Verification

### 7.1 What was observed on the reference build

Oracle: enumerate the process's visible top-level windows after a fixed wait, record the titles.

```text
patched, licence registry values present
  windows: count=2
    title=[UltraISO Premium Edition]
    title=[UltraISO]
  process closes cleanly

patched, UserName and Registration values deleted first
  windows: count=2
    title=[UltraISO Premium Edition]
    title=[UltraISO]

shipped, licence registry values present (baseline)
  windows: count=2
    title=[Welcome]
    title=[UltraISO]
```

The `Welcome` window is the trial modal. It is absent in both patched runs, including the run with no licence values in the registry at all, which proves the patch does not depend on the registry pair. The second title in each list is the hidden VCL main-window handle for the same form, not a second dialog.

Live flag sampling, same session, RVA `0x2EBEE0`, with the caption literal read in the same pass to prove the address mapping:

```text
0.2 s  flag=0  windows=UltraISO Premium Edition|UltraISO
345 s  flag=0  windows=UltraISO Premium Edition|UltraISO   (23 samples, no transition)
```

The file hash and the four site bytes are the primary evidence. Window titles are secondary. The flag value is reported because it is a trap, not because it is the goal.

### 7.2 Matrix that must pass

| Step | Expected |
|---|---|
| `Apply` on a pristine copy | output hash `31896FFD...`, 27 bytes differ |
| `Apply` again on the patched copy | `already patched, nothing to do`, mtime unchanged |
| `Apply` on a build with one site altered | refusal, file untouched |
| `Apply` on a different executable | refusal on size, file untouched |
| `Apply` while `UltraISO.exe` runs | refusal naming the pid |
| `Restore` | hash returns to `F89E9D33...` |
| Launch patched | no `Welcome` window, caption `UltraISO Premium Edition` |
| Launch patched with the registry pair deleted | no `Welcome` window |
| Save an image larger than the trial cap | save completes, no `Sorry, Trial Version Cannot Save File above 300MB!` message |

The last row is open. Drive it through the GUI: launch the patched build, add a directory containing more than 300 MB in files, `Save As`, and watch for the message box whose text sits at file offset `0x2E7C8F` (VA `0x2E868F`). If it appears, the cap has its own site and this patch is incomplete for large images; the next step is to find the code that loads that string and the size comparison that precedes it, which is a separate job from the startup gate.

### 7.3 Patcher matrix as observed

```text
1 Check pristine copy                 exit 0  state pristine
2 Apply pristine copy                 exit 0  output 31896FFD..., backup F89E9D33...
3 Apply again                         exit 0  already patched, hash and mtime unchanged
4 Apply, one site altered             exit 1  patch sites do not match any known state, file untouched
5 Apply, different executable         exit 1  unsupported size 800933, file untouched
6 Apply while UltraISO runs           exit 1  UltraISO is running (pid 14860), file untouched
7 Restore                             exit 0  hash back to F89E9D33...
```

Row 3 is a no-op before the running-process check, which is deliberate: nothing is written, so an open target is not an error.

## 8. Registry

The patch does not need the registry pair. The loader still runs, so the About box name comes from `HKCU\SOFTWARE\EasyBoot Systems\UltraISO\5.0` value `UserName` if present. With no values at all the application still opens as retail and the caption is correct.

Deleting the values is a valid way to prove the patch is registry independent:

```text
reg delete "HKCU\SOFTWARE\EasyBoot Systems\UltraISO\5.0" /v UserName /f
reg delete "HKCU\SOFTWARE\EasyBoot Systems\UltraISO\5.0" /v Registration /f
```

This repository does not publish licence codes or a key generator. The one legitimate reason to know the encoding is to recognise a stored pair while reversing: the code is XOR-obfuscated with an 8-byte rotating constant and the user name, and the validator is the RSA check in section 3.1.

## 9. Rollback

- Pristine backup: `<backup-dir>\UltraISO.exe.orig`, default `%ProgramData%\ultraiso-patch\backup`.
- Pristine hash: `F89E9D336C6F49FBD847EA513A11BB1BFA80EA5FD1336E23CAD7D80370BAEA65`.
- Restore: `patch-ultraiso.ps1 -Mode Restore`, which re-checks the backup hash before writing and re-checks the target hash after.
- Manual restore: copy the backup over `<install-dir>\UltraISO.exe` and confirm the hash.

Keep the backup outside the install directory. A pristine copy inside the install folder gets picked up by media builds and by installer repair logic, which has produced confusing half-patched boot images in other projects.

## 10. Finding the sites in a new version

### 10.1 Anchors that survived

| Anchor | How to find it | Uniqueness on 9.7.6.3829 |
|---|---|---|
| Licence decision cluster | bytes `a3 e0 be 6e 00 8b 15 e0 be 6e 00 85 d2 74` (`mov [flag],eax; mov edx,[flag]; test edx,edx; je`) | one match, file `0x264D` |
| Caption literal | ASCII `(Trial Version)` | one match, file `0x2E7355` |
| Retail wording already in the product | ASCII `Premium Edition` | present at file `0x4C1CA8` in resources, use the same words |
| Nag guard | `mov ecx,[X]; mov eax,[Y]; cmp ecx,eax; je` immediately after the class lookup for `TfrmStartup` | reachable from the cluster by falling forward |

### 10.2 Recomputing offsets

1. Parse the PE header: image base, section table, and the section containing the VA.
2. Convert with `offset = va - image_base - section.vaddr + section.rawptr`.
3. Confirm the bytes at the computed offset equal the recorded original bytes. If they do not, the anchor moved; do not guess.

`patcher/src/patch-ultraiso.ps1` carries the four VAs and offsets as one table, so a new build is a table edit plus a new hash, not a rewrite.

### 10.3 What to re-check on a new build

- The loader call must still precede the flag store, and the validator call must still sit inside the branch that the flag store follows. If the order changes, site 1 and site 2 need to move together.
- The nag guard may compare different globals. What matters is that it is the branch that skips the `TfrmStartup` block.
- The caption literal may be a different length. If it is, pick wording of exactly that length or move the string to a cave, and note the change.
- The re-evaluation writer in section 3.2 may move. Find it by searching for the immediate store `c7 05 e0 be 6e 00 01 00 00 00` (the "write 1" half) and walking backwards. Patching it changed nothing measurable on this build.

## 11. Limits

- **Signature.** The patched file still carries the original Authenticode blob, so its signature reports `HashMismatch`. Windows loads it, but Smart App Control and some application-control policies refuse modified signed binaries. On a machine that enforces SAC, this patch does not run and there is no way around that short of signing with a trusted key.
- **PE checksum.** Not recomputed; it is irrelevant to loading a user-mode executable and UltraISO was observed not to check itself.
- **About dialog.** Not verified. It reads the name the loader fills. With no registry values it is expected to show an empty or placeholder name while the caption and behaviour are retail. Check it before quoting the build as fully clean.
- **Save cap.** Open. The trial message text is present in the binary and the cap is described by the vendor as removed by registration, so assume it is enforced until a >300 MB save is observed succeeding. The flag it most likely reads is 0 during the session even after a forced write (section 3.2), so this needs its own site if the message appears. Test it as described in section 7.2 before promising a fully working retail build.
- **Long session behaviour.** Sampled for 345 s with no window change and no nag reappearing. That is a short session: an idle soak of a few hours is the honest test before calling it stable.
- **Network.** No outbound licence check was observed at startup. "Not observed" is not "not present"; if the vendor adds one, this patch will not satisfy it.
- **Distribution.** Do not commit the patched executable, the backup, or any licence code. Publish the offsets and the patcher source, as this repository does.
