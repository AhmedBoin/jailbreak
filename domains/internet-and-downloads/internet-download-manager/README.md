# Internet Download Manager

Domain: `internet-and-downloads`

Target: Internet Download Manager 6.43 build 18, 32-bit native build.

Status: registered state, warning suppression, buy-page suppression, update-check suppression, helper-dialog suppression, the crypt32 module unload crash fix, and inside dialog suppression. The complete build is the inside build in playbook sections 14, 15 and 16.

This project is a guide only. It ships no patched binary, no keygen, and no compiled patcher. Build the patched file locally from the playbook if you need it.

## What is included

| File | Purpose |
|---|---|
| `playbook.md` | Full analysis, offsets, registry setup, discovery workflow, verification, rollback |
| `README.md` | Scope, patch summary, and quick start |

## Quick start

1. Close `IDMan.exe`.
2. Back up `IDMan.exe` and `IDMGrHlp.exe` outside the install directory.
3. Apply the byte patches in the playbook to IDMan.exe and IDMGrHlp.exe.
4. Apply site 37 at file `0x478B1` (7 NOPs).
5. Apply site 38: write the 35-byte resident stub at file `0x2D6A4C` and set `AddressOfEntryPoint` to RVA `0x2D764C`.
6. Apply the section 15 patches: site 40 dialog procedure jump at `0x250B62`, the 79-byte cave at `0x2D6A80`, site 41 warning function at `0x73B60`, site 42 licensed-to call at `0x893A6`, and site 43 dialog wrapper call at `0xA7F86`.
7. Recompute the PE `CheckSum` and write it at file `0x150`. Do this after every code patch.
8. Create the four registry values under `HKCU\Software\DownloadManager`. Use a random 5-5-5-5 serial, not `12345-67890-12345-67890`.
9. Start IDM and confirm `idmvers` changes from `v6.43b18 Trial` to `v6.43b18 Full`.
10. Confirm `Crypt32.dll` is in the 32-bit module list immediately after launch.
11. Open the Registration dialog. No registration window, no fake-serial warning, and no licensed-to message may appear.
12. Add a download and confirm that only the standard `Download File Info` and `Download complete` windows appear.
13. Confirm that no buy page opens and that `LastCheckQU` does not change.
14. Leave IDM in the tray for 25 minutes. The process must stay alive, `Crypt32.dll` must stay in the module list, and no damaged-file dialog may appear.

The authoritative build path is the complete script in playbook section 16. It reproduces the installed inside file byte for byte from the pristine binary and verifies SHA256 `199E459FCC1D4ECDFDF3649C8E708FEE5EEC07CA22BD5AA9C253077B11F3BC6D`.

## Patch summary

All offsets are file offsets for the named binary. The helper offsets are for `IDMGrHlp.exe` 6.35.9.1.

| Offset | Original | Patch | Purpose |
|---:|---|---|---|
| `0x4FFC4` | `74 15` | `EB 15` | Force the online registration branch to success |
| `0x5A4B0` | `55 8B EC` | `B0 01 C3` | Registration name validator returns true |
| `0x5A830` | `55 8B EC` | `B0 01 C3` | Serial validator returns true |
| `0x50C1C` | `B8 03 00 00 00` | `B8 00 00 00 00` | Counterfeit status becomes registered status |
| `0x93B5F` | `E8 FC FF FD FF` | `31 C0 90 90 90` | Skip the first fake-serial warning |
| `0x74E84` | `E8 D7 EC FF FF` | `31 C0 90 90 90` | Skip the second fake-serial warning |
| `0x55DD0` | `55 8B EC` | `33 C0 C3` | Disable the automatic update check |
| `0x7C1A0` | `55` | `C3` | Disable the first buy-page URL builder |
| `0x7EA43` | `E8 B8 7C 03 00` | `31 C0 90 90 90` | Skip the timer buy-page opener |
| `0x863E9` | `0F 84 78 01 00 00` | `E9 79 01 00 00 90` | Force the timer's registered path to stop the exit |
| `0x478B1` | `50 FF 15 C0 84 6D 00` | `90 90 90 90 90 90 90` | Site 37: drop the destructor `FreeLibrary` of the cached crypt32 handle |
| `0x2D6A4C` | zero padding | 35-byte stub (playbook 14.12) | Site 38: load `Crypt32.dll` at the entry point and hold the reference |
| `0x250B62` | `8B FF 55 8B EC` | `E9 19 5F 08 00` | Site 40: dialog procedure jumps to the cave |
| `0x2D6A80` | zero padding | 79-byte cave (playbook 15.1) | Site 40 cave: close the title length 38 registration dialog |
| `0x73B60` | `6A FF 68 88 78 6A` | `31 C0 C3 88 78 6A` | Site 41: warning function returns 0 |
| `0x893A6` | `E8 F5 24 06 00` | `31 C0 90 90 90` | Site 42: skip the licensed-to confirmation |
| `0xA7F86` | `FF 15 68 86 6D 00` | `31 C0 90 90 90 90` | Site 43: skip the custom dialog wrapper |
| `0x150` | `C4 55 64 00` | `F7 B6 63 00` | PE `CheckSum` for the complete build, recomputed after all patches |

Site 37 alone is not enough. IDM loads `Crypt32.dll` at `0x5EF4D2`, caches the handle at `[0x7D2064]`, and calls `CertFindChainInStore` through the cached pointer at `0x5EF517`. The destructor free at `0x4484B2` is one unload source, but the certificate path also calls `LdrUnloadDll` on the crypt32 base from KERNELBASE. When the last reference goes, the process dies with `0xc0000005` in `CRYPT32.dll_unloaded` at offset `0x5d220`. Site 38 loads crypt32 at the entry point and never frees it, so one reference survives every unload and the cached pointer stays valid. The section 15 patches suppress the registration UI directly: the dialog procedure stub closes the title length 38 registration window, the warning function returns 0, and the licensed-to and wrapper calls are skipped. The status function at `0x4FA30` remains original.

The old site 39 status stub at `0x4FA30` (`31 C0 C3`) is obsolete. It forces the display to Trial and does not stop the download-time licensed-to dialog. Do not apply it; the inside build keeps `55 8D AC` at that offset.

The `0x150` row is site 31. It is header hygiene, not the crash fix: a 31-site build with a correct checksum still died at `crypt32+0x5D220`. The value must be recomputed for any other patch order or build; see playbook section 14.

### Tray and exit overlay

The base table stops the buy page, the fake-serial warnings, and the update check. The tray and exit behavior needs this additional overlay:

| Offset | Original | Patch | Purpose |
|---:|---|---|---|
| `0x914DD` | `FF 15 44 E5 7C 00` | `E8 A5 13 03 00 90` | Replace the timer `ShellExecuteA` call with a `ret 0x18` gadget |
| `0x88C15` | `8B 75 08 8B C6` | `E9 DA 0A 00 00` | Redirect `WM_CLOSE` to the hide-to-tray cave |
| `0x896F4` | `CC` x 34 | cave code | Hide the window and return 0 on `WM_CLOSE` |
| `0x8DA76` | `68 10 27 00 00` | `68 FF FF FF 7F` | Disable the 10 second exit timer |
| `0x6C073` | `8D 8E 20 4E 00 00 51` | `68 FF FF FF 7F 90 90` | Disable the 32 second exit timer |
| `0x6C08C` | `75 41` | `90 90` | Remove the timer exit branch |
| `0x6C09A` | `E8 B1 72 FB FF` | `83 C4 0C 90 90` | Skip the 12 second registration timer |
| `0x101D4` | `FF 15 04 85 6D 00` | `E8 06 05 FF FF 90` | Neutralize the first stray `ExitProcess` call |
| `0x4D006` | `FF 15 04 85 6D 00` | `E8 D4 36 FB FF 90` | Neutralize the second stray `ExitProcess` call |
| `0x6640B` | `FF 15 04 85 6D 00` | `E8 CF A2 F9 FF 90` | Neutralize the third stray `ExitProcess` call |
| `0x6C0CF` | `FF 15 04 85 6D 00` | `E8 0B 46 F9 FF 90` | Neutralize the fourth stray `ExitProcess` call |
| `0x120D5C` | `FF 15 04 85 6D 00` | `E8 7E F9 ED FF 90` | Neutralize the fifth stray `ExitProcess` call |

### Residual quit overlay

The section above still lets the message loop end: `PostQuitMessage` makes `GetMessage` return 0, `WinMain` returns and the CRT calls `ExitProcess` at `0x680087`, which no patch covers. Measured on the 22-site build, an untouched window dies at 180.3 s and a hidden window dies after `WM_CLOSE`. This overlay adds eight sites and makes the 30-site build.

| Offset | Original | Patch | Purpose |
|---:|---|---|---|
| `0x76665` | `68 20 BF 02 00` | `68 FF FF FF 7F` | Timer 21 arm A becomes INFINITE |
| `0x8DA5C` | `68 20 BF 02 00` | `68 FF FF FF 7F` | Timer 21 arm B becomes INFINITE |
| `0x14E902` | `FF 15 5C 86 6D 00` | `58 90 90 90 90 90` | Tray `WM_DESTROY`: no `WM_QUIT` |
| `0xB7E27` | `FF 15 5C 86 6D 00` | `58 90 90 90 90 90` | Second `PostQuitMessage` site |
| `0xE21BE` | `FF 15 5C 86 6D 00` | `58 90 90 90 90 90` | Third `PostQuitMessage` site |
| `0xE2647` | `FF 15 5C 86 6D 00` | `58 90 90 90 90 90` | Fourth `PostQuitMessage` site |
| `0x101DA` | `CC` | `C3` | `int3` after site 18 becomes `ret` |
| `0x25F5A0` | `FF 25 5C 86 6D 00` | `C3 90 90 90 90 90` | Tail-jump thunk to `PostQuitMessage` becomes `ret` |

The two timer arms are `SetTimer(hwnd, 0x15, 180000, NULL)` in the initializers at `0x476000` and `0x48E5C0`; site 14 had only disabled the 10-second twin. Each `PostQuitMessage` site replaces `call dword [0x6D865C]` with `pop eax` plus five NOPs: `pop` removes the argument that the preceding `push` placed, so the stack depth, return address and SEH chain are unchanged and no cave is used. The tail-jump thunk at `0x25F5A0` becomes `ret`, so no reference to the `PostQuitMessage` IAT slot remains. The site at `0x101DA` turns the `int3` behind site 18 into `ret`, so even a return through the neutralized `ExitProcess` call continues instead of raising `STATUS_BREAKPOINT`. See playbook section 13.

The cave at `0x896F4` is:

```text
8B 75 08 83 FE 10 74 0A 8B C6 83 E8 01 E9 17 F5 FF FF
6A 00 FF 77 20 FF 15 DC 87 6D 00 E9 34 F5 FF FF
```

It checks for `WM_CLOSE`, calls `ShowWindow(hwnd, SW_HIDE)`, and returns 0 through the normal function epilogue.

### IDMGrHlp helper overlay

`IDMGrHlp.exe` shows the periodic fake-serial dialogs. Apply these two patches to the helper:

| Offset | Original | Patch | Purpose |
|---:|---|---|---|
| `0x52A1` | `FF 15 BC 34 44 00` | `31 C0 90 90 90 90` | Suppress the short fake-serial dialog |
| `0x52C8` | `FF 15 BC 34 44 00` | `31 C0 90 90 90 90` | Suppress the long fake-serial dialog and its URL branch |

## Registry

Create these values under `HKCU\Software\DownloadManager`:

```text
Serial  REG_SZ  A7K2M-9Q4XZ-3V8NB-6T1WP
FName   REG_SZ  Test
LName   REG_SZ  User
Email   REG_SZ  test@example.com
```

The serial must be 23 characters with hyphens at positions 5, 11, and 17, for example `XXXXX-XXXXX-XXXXX-XXXXX`. Use a synthetic value, not a leaked key. Do not use `12345-67890-12345-67890`; it is blacklisted and triggers the licensed-to path even with the section 15 patches.

## Reference build

```text
size            6,517,616 bytes
pristine SHA256 A705C0154FAFC7CD509DECF165CB6F6C050B6521B40ADB6F730DD827C86051C7
30-site SHA256  0D822AB317069F4B460A6B8333A26B56C8E527E080077212FB3E0209BD6CD395
37-site SHA256  3A63B29E905C24C823F19F25D27405B468FFC8092AD9C84BC8A4B1E4DC16D2B7
38-site SHA256  64BF39DD3BDD568389C84CF3546B4007B2B97775F728E485F670DFCBBF720DA0
39-site SHA256  599B15C25C1B9F06DCC4049B88E332AA105BBC0C382423F86BEC0D15F2224085 (superseded)
inside SHA256   199E459FCC1D4ECDFDF3649C8E708FEE5EEC07CA22BD5AA9C253077B11F3BC6D

IDMGrHlp.exe
size            519,992 bytes
pristine SHA256 B3B6281EA820EAE8192E50B30698CF4C3B8BC3D4376C978403BC9E18E5857C23
patched SHA256  F5E7360A0C376247507218AC92392BD8B71AF70376E3BF1058C77AFED575B36D
```

The 30-site hash is `IDMan.exe` with the base set, the tray and exit overlay, and the residual quit and timer overlay. It still dies after 20 to 25 minutes because of the crypt32 module unload race in playbook section 14. The 37-site hash adds site 37 and still crashes because the certificate path unloads crypt32. The 38-site hash adds the entry-point resident stub (site 38). The 39-site hash adds the obsolete registration status stub (site 39) and is superseded. The inside hash adds the section 15 dialog patches and is the current build, with PE `CheckSum` `0x0063B6F7`. The intermediate 22-site build is `BACF3DCC44073935FD72493A2578F0A7295FE2F447A9DCF68EC0C4CD3774A020`. The helper hash is for `IDMGrHlp.exe` with the two dialog patches. A different patch order or a new build produces a different hash.

## Updates

An IDM update replaces `IDMan.exe` and `IDMGrHlp.exe` and restores the original bytes. Re-run the discovery workflow in the playbook, update the offsets, and re-apply the full set.

The update check is disabled by the `0x55DD0` patch. Manual `Help -> Check for updates` remains a separate action.

## Distribution policy

This repository publishes analysis and guides, not ready-to-run cracks. Do not commit a patched `IDMan.exe`, a keygen, a license generator, or a compiled patcher for this project. The playbook contains the offsets and the local procedure.

## Full playbook

Open [`playbook.md`](playbook.md).

## License

MIT. See the repository [`LICENSE`](../../../LICENSE).
