# Internet Download Manager

Domain: `internet-and-downloads`

Target: Internet Download Manager 6.43 build 18, 32-bit native build.

Status: registered state, warning suppression, buy-page suppression, and update-check suppression verified locally.

This project is a guide only. It ships no patched binary, no keygen, and no compiled patcher. Build the patched file locally from the playbook if you need it.

## What is included

| File | Purpose |
|---|---|
| `playbook.md` | Full analysis, offsets, registry setup, discovery workflow, verification, rollback |
| `README.md` | Scope, patch summary, and quick start |

## Quick start

1. Close `IDMan.exe`.
2. Back up `IDMan.exe` outside the install directory.
3. Apply the eight byte patches in the playbook.
4. Create the four registry values under `HKCU\Software\DownloadManager`.
5. Start IDM and confirm `idmvers` changes from `v6.43b18 Trial` to `v6.43b18 Full`.
6. Add a download and confirm that no counterfeit dialog and no fake-serial warning appear.
7. Confirm that no buy page opens and that `LastCheckQU` does not change.

## Patch summary

All offsets are file offsets for the 6.43 build 18 `IDMan.exe`.

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

The cave at `0x896F4` is:

```text
8B 75 08 83 FE 10 74 0A 8B C6 83 E8 01 E9 17 F5 FF FF
6A 00 FF 77 20 FF 15 DC 87 6D 00 E9 34 F5 FF FF
```

It checks for `WM_CLOSE`, calls `ShowWindow(hwnd, SW_HIDE)`, and returns 0 through the normal function epilogue.

## Registry

Create these values under `HKCU\Software\DownloadManager`:

```text
Serial  REG_SZ  12345-67890-12345-67890
FName   REG_SZ  Test
LName   REG_SZ  User
Email   REG_SZ  test@example.com
```

The serial must be 23 characters with hyphens at positions 5, 11, and 17, for example `XXXXX-XXXXX-XXXXX-XXXXX`. Use a synthetic value, not a leaked key.

## Reference build

```text
size            6,517,616 bytes
pristine SHA256 A705C0154FAFC7CD509DECF165CB6F6C050B6521B40ADB6F730DD827C86051C7
patched SHA256  BACF3DCC44073935FD72493A2578F0A7295FE2F447A9DCF68EC0C4CD3774A020
```

The patched hash is for the full base set plus the tray and exit overlay. A different patch order or a new build produces a different hash.

## Updates

An IDM update replaces `IDMan.exe` and restores the original bytes. Re-run the discovery workflow in the playbook, update the offsets, and re-apply the full set.

The update check is disabled by the `0x55DD0` patch. Manual `Help -> Check for updates` remains a separate action.

## Distribution policy

This repository publishes analysis and guides, not ready-to-run cracks. Do not commit a patched `IDMan.exe`, a keygen, a license generator, or a compiled patcher for this project. The playbook contains the offsets and the local procedure.

## Full playbook

Open [`playbook.md`](playbook.md).

## License

MIT. See the repository [`LICENSE`](../../../LICENSE).
