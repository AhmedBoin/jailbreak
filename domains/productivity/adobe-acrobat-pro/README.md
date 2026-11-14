# Adobe Acrobat Pro (25.1)

Domain: `productivity`

Target: Adobe Acrobat 25.1, native x64 build. The worked example is 25.1.21208.0
(`Acrobat.exe`), NGL client 25.1.21208.7, `Acrobat.dll` 25.1.21208.7.

Status: desktop verified on Windows 11, x64.

This project is a guide only. No binary, patcher, script, or pre-patched DLL is in the
repository.

## The result

Two writes in `Acrobat.dll` turn the installed application into Acrobat Professional
without an account and without the trial sheet:

| Decision | RVA | Original | Patch |
|---|---:|---|---|
| Entitlement level | `0x6DA6D1` | `BB 01 00 00 00` | `BB 2C 01 00 00` |
| Workflow initializer | `0x6E248C` | `48 8B C4` | `33 C0 C3` |

The first makes the local entitlement 300 (Professional) instead of 1 (Reader). The
second makes `InitializeWorkflows` return immediately, so the CEF licensing host that
paints the trial sheet is never created, and the synchronous wait that freezes the UI
when that host is killed or stubbed never happens.

The write itself is two stores, not two programs: once the two addresses are known,
the patch is complete in well under a second. Locating them on a new build is the only
real work, and phase 4 is the loop that does it from runtime evidence rather than from
a byte diff.

## What is included

| File | Purpose |
|---|---|
| `playbook.md` | Full model, exact sites, relocation loop, verification matrix, rollback |
| `README.md` | Scope, patch summary, quick start |

## Quick start

1. Close every Acrobat process.
2. Copy `Acrobat.dll` out of the install directory as a backup.
3. Write the two patches above at file offsets `0x6D9AD1` and `0x6E188C`.
4. Read both ranges back and compare with the patch bytes.
5. Start Acrobat and verify with the matrix in phase 6.

File offset for this build is `0x400 + (RVA - 0x1000)`, from the `.text` section
header. A different build needs the relocation loop first, never a blind write.

## Reference build

```text
Acrobat.dll size            79,011,288 bytes
pristine SHA256             F58581CBC18B4284B12E42399B4E0C2C6A18FBFB26824AA7E3B0917D5E7621FE
patched SHA256              4FC9D1DC55EAE69637D3E13E8E55F04CABCA58C0747E8983DCF91A6B857BB3BE

Acrobat.exe size            6,399,960 bytes
FileVersion                 25.1.21208.0
.text VirtualAddress        0x1000
.text PointerToRawData      0x400
```

Any tool that applies this should refuse a file whose size or original bytes do not
match, and should verify the write before the next launch.

## Verification

A run passes only if all of these hold:

- `%TEMP%\acroNGLLog.txt` reports `Entitlement is 300` and
  `ACROBAT LICENSE CHANGE NOTIFICATION : Entitlement is Acrobat Professional.`
- `HKCU\SOFTWARE\Adobe\Adobe Acrobat\DC\AVEntitlement\iEntitlementLevel` stays 300.
- `app.viewerType` from a PDF OpenAction returns `Exchange-Pro`.
- A Pro-only API call such as `addWatermarkFromText` succeeds.
- No `adobe_licensing_wf_acro.exe` process appears during a 60 second cold start, and
  the main window answers window messages the whole time.

## Updates

An Acrobat update replaces `Acrobat.dll` and removes both patches. Re-run the
relocation loop, then reapply. Do not reuse the RVAs on a new build without checking
the original bytes.

## Full playbook

Open [`playbook.md`](playbook.md).

## License

MIT. See the repository [`LICENSE`](../../../LICENSE).
