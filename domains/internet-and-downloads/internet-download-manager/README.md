# Internet Download Manager

Domain: `internet-and-downloads`

Target: Internet Download Manager 6.x, 32-bit native builds. The worked example is 6.43 build 18.

This folder is an executable runbook for an agent, not a fixed patch list. The playbook explains how to find the decision each layer makes, how to confirm the decision at runtime, how to patch it, and how to prove the result. The manifest and tools are the reference implementation for 6.43 build 18.

## What is included

| Path | Purpose |
|---|---|
| `playbook.md` | Phase-based runbook: recon, license, UI, lifecycle, crypt32, helper, build, verify, drift |
| `manifest/6.43b18.json` | 38 verified patches with original and patch bytes, and the expected output hash |
| `manifest/6.43b18-nag.json` | Addendum that stubs the trial nag page thread (section 4.6) |
| `tooling/patch.py` | Applies a manifest, verifies original bytes and overlaps, recomputes the PE checksum, checks `expected_sha256` |
| `tooling/hook-status.py` | Spawns IDMan under Frida and reports the live status code, dialogs, and exit calls |
| `tooling/hook-status.js` | The Frida probe body, editable for extra hooks |
| `tooling/gate.ps1` | Static manifest check plus launch, tray, WER, and optional transfer tests |
| `tooling/nag-probe.py` | Spawns IDM under Frida and logs windows, classes, registry reads and shell calls |

## Quick start

```text
# 1. Probe the build you have. Read the status code before patching.
python tooling/hook-status.py "<pristine>\IDMan.exe" --seconds 8

# 2. Apply the manifest for this exact build.
python tooling/patch.py manifest/6.43b18.json "<pristine>\IDMan.exe" "<build>\IDMan.exe"

# 2b. Apply the nag addendum to the manifest output.
python tooling/patch.py manifest/6.43b18-nag.json "<build>\IDMan.exe" "<build>\IDMan.nag.exe"

# 3. Static and dynamic acceptance on the build copy.
powershell -File tooling/gate.ps1 -Exe "<build>\IDMan.nag.exe" -Manifest manifest/6.43b18-nag.json -AliveSeconds 20 -TraySeconds 15

# 4. Install, then run the gate against the installed file.
powershell -File tooling/gate.ps1 -Exe "C:\Program Files (x86)\Internet Download Manager\IDMan.exe" -Manifest manifest/6.43b18-nag.json
```

## Read this first

1. Keep a pristine `IDMan.exe` and `IDMGrHlp.exe`, plus a registry export of `HKCU\Software\DownloadManager`.
2. Probe the status dispatcher at runtime. A build that passes a static byte check can still return 6 (trial expired) and open the registration window.
3. Fix the status machine before the UI. Dismissing the registration dialog while the status is non-zero produces a silent exit with code 2.
4. Run only one IDMan at a time. A second instance exits in a fraction of a second and looks like a broken patch.
5. Verify on a copy with `ExePath` set to that copy, then install.
6. A build is done when the verification matrix passes, including the tray soak and the browser transfer test.
7. The `You have N days left` page is a separate worker thread, not a message box. If it appears after a passing gate, the nag addendum was not applied (section 4.6).

## Layers

| Layer | What to do |
|---|---|
| Registry | Set `Serial`, `FName`, `LName`, `Email`, `ExePath`. Use a synthetic serial that matches the 23-character format. |
| Validators | Make the name and serial validators return true. |
| Status | Read the live code, then patch the `mov eax, imm32` for each non-zero code the machine returns. |
| Registration UI | Redirect the registration dialog procedure to a cave that closes only that dialog. |
| Warning and licensed-to | Patch the warning function and the licensed-to call. |
| Trial nag page | Stub the HTML page thread at `0x73A10` (section 4.6). |
| Buy page and update | Patch the URL builder, the `ShellExecute` call, and the update check. |
| Lifecycle | Raise the exit timers to INFINITE, neutralize `PostQuitMessage` and `ExitProcess`, hide on `WM_CLOSE`. |
| Crypt32 | Remove the free, or hold a reference at the entry point. |
| Helper | Skip the `MessageBox` calls in `IDMGrHlp.exe`. |
| Checksum | Recompute the PE checksum after every code patch. |

## Verified reference build

```text
IDMan.exe 6.43 build 18, 6,517,616 bytes
pristine  A705C0154FAFC7CD509DECF165CB6F6C050B6521B40ADB6F730DD827C86051C7
output    98D9E4085759E13836E3063C5E11FA75770A974582FA8890F39A290A83ECE260
checksum  0x00645141 at file 0x150
```

With the nag addendum (`6.43b18-nag.json`):

```text
output    65398CC64E5E2D87C3D54B5141A6EB3720F3302E29B7766CC800CFDC3B6966BC
checksum  0x006385F5 at file 0x150
```

The manifest reproduces the output hash from the pristine file exactly. That comparison is the acceptance test for the manifest itself.

## Browser transfer

If the browser reports `Cannot transfer the download to IDM`, `Error 0x80010108`, IDM is not running. `0x80010108` is `RPC_E_DISCONNECTED`: the extension's automation server is gone. Fix the IDM startup path, not the extension. Test with:

```text
IDMan.exe /d "https://example.com/file.zip"
```

## Version drift

Offsets move. Strings, imports, registry names, serial format constants, dialog titles, status codes, and call shapes stay useful. Start from the anchor, confirm the decision at runtime, patch one layer, run that layer's gate. Rebuild the manifest by diffing pristine against the patched file, then reproduce the output hash before installing.

## Distribution

This repository ships the method, the manifest, and the tools, not a patched binary. Do not commit a patched `IDMan.exe`, a keygen, or a compiled patcher.
