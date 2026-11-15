# UltraISO Premium 9.7.6.3829

Domain: `disk-and-partition`

Target: UltraISO Premium 9.7.6.3829 (EZB Systems), PE32 x86, `UltraISO.exe`, 5,543,368 bytes.

Status: desktop verified on Windows 11 x64, with and without licence values in the registry.

## The result

Four byte-level edits, 27 bytes total, turn the installed trial into the retail build. No registry pair, no key, no server, no patched binary published here.

| Decision | VA | File offset | Original | Patch |
|---|---|---:|---|---|
| Forced validate branch | `0x403052` | `0x002652` | `8b 15 e0 be 6e 00` | `ba 01 00 00 00 90` |
| Validator result | `0x40306A` | `0x00266A` | `e8 9d e8 ff ff` | `b8 01 00 00 00` |
| Startup nag branch | `0x4030A8` | `0x0026A8` | `74 19` | `eb 19` |
| Caption literal | `0x6E7D55` | `0x2E7355` | `(Trial Version)` | `Premium Edition` |

The first two take the branch that runs the validator and leave the licence loader running, so the loader still fills the name and code the About box reads. The third skips the `TfrmStartup` "Welcome" modal. The fourth replaces the trial suffix in the runtime-composed window caption with the wording the product already uses elsewhere.

Removing only the modal is the common mistake: the caption survives, and the licensed flag at `0x6ebee0` (38 references in `.text`) is a separate decision that does not stay at 1 on this build even when forced. Section 3.2 of the playbook records the measurements, including the second writer at `0x4241FC` and the five-site build that changed nothing.

File offset is `va - image_base - section.vaddr + section.rawptr`. For `.text` that is `va - 0x400A00`; for `.data` it is `va - 0x4900`.

## What is included

| File | Purpose |
|---|---|
| `playbook.md` | Licence flow, disassembly, exact sites, reproduction, verification matrix, rollback, discovery for a new build |
| `patcher/src/patch-ultraiso.ps1` | Standalone patcher source: Check, Apply, Restore, build locked, atomic write, refuses a running process |
| `patcher/build.ps1` | One-command build: parse check plus copy to `dist/` |
| `patcher/README-Patcher.txt` | Run, build, backup, and safety notes |
| `patcher/dist/` | Local build output, ignored by git |

No patched executable, backup, keygen, or licence code is in this repository.

## Quick start

```text
powershell -NoProfile -ExecutionPolicy Bypass -File patcher\build.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File patcher\dist\patch-ultraiso.ps1 -Mode Check
powershell -NoProfile -ExecutionPolicy Bypass -File patcher\dist\patch-ultraiso.ps1 -Mode Apply
```

1. Close every UltraISO process.
2. Run `Check`. It must print `state : pristine` and `sha256 : F89E9D33...`.
3. Run `Apply`. It writes the pristine backup to `%ProgramData%\ultraiso-patch\backup`, patches the four sites, and verifies the result.
4. The expected output hash is `31896FFD80D167F8B791F24C5EDAE0CAB083F2F56EE825A22D78C490B869192D`.
5. Start UltraISO. There is no `Welcome` window and the caption reads `UltraISO Premium Edition`.
6. To undo, run `-Mode Restore`.

Apply needs write access to the install directory and raises a UAC prompt when it does not have it. `-NoElevate` makes it fail instead of prompting, which is the mode to use for testing against copies.

## Reference build

```text
UltraISO.exe size           5,543,368 bytes
pristine SHA256             F89E9D336C6F49FBD847EA513A11BB1BFA80EA5FD1336E23CAD7D80370BAEA65
patched SHA256              31896FFD80D167F8B791F24C5EDAE0CAB083F2F56EE825A22D78C490B869192D
FileVersion                 9.7.6.3829
image base                  0x400000
.text                       VirtualAddress 0x1000, PointerToRawData 0x600
.data                       VirtualAddress 0x27F000, PointerToRawData 0x27E600
```

The patcher refuses any other size, any other source hash, and any file whose sites are neither pristine nor already patched.

## Verification

- Windows after a clean start: no window titled `Welcome`, main caption `UltraISO Premium Edition`, process exits normally, no nag during a 345 second idle sample.
- Same result with `UserName` and `Registration` deleted from `HKCU\SOFTWARE\EasyBoot Systems\UltraISO\5.0`, so the patch does not depend on stored licence values.
- Two independent patch routes produce the same 27-byte diff and the same output hash.
- Open: the >300MB save path and the About dialog text. Both are named with the check to run in the limits section of the playbook.

## Updates

There is no in-app updater in the install folder. A reinstall or a new release replaces `UltraISO.exe` and drops all four patches. Locate the sites again with the anchors in section 10 of the playbook; do not reuse the offsets without checking the original bytes first.

## Full playbook

Open [`playbook.md`](playbook.md).

## License

MIT. See the repository [`LICENSE`](../../../LICENSE).
