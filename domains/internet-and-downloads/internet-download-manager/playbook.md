# Internet Download Manager Playbook

Target: Internet Download Manager 6.43 build 18

File: `IDMan.exe`

Architecture: 32-bit x86, PE32, native C++

Status: inside build installed and verified on 2026-11-14; see section 14.10

This playbook describes a local patch set. It does not ship a patched binary or a compiled patcher.

## 1. Target profile

| Item | Value |
|---|---|
| Vendor | Tonec Inc. |
| Product | Internet Download Manager |
| Version | 6.43 build 18 |
| Install directory | `%ProgramFiles(x86)%\Internet Download Manager` |
| Main executable | `IDMan.exe` |
| Helper executable | `IDMGrHlp.exe` (6.35.9.1) |
| Architecture | x86 |
| Framework | Native C++ with MFC-style dialogs |
| Packer | None |
| License storage | Registry, `HKLM\SOFTWARE\WOW6432Node\Internet Download Manager` or `HKCU\Software\DownloadManager` |
| Online check | Yes, against `secure.internetdownloadmanager.com` |
| Update check | Yes, `LastCheckQU` timestamp plus `IDMGrHlp.exe` |
| Buy page | `https://secure.internetdownloadmanager.com/buy_idm2.html` |

The installer creates a 32-bit process. On 64-bit Windows the registry view is `WOW6432Node`.

## 2. Reference build

```text
file            IDMan.exe
size            6,517,616 bytes
image base      0x00400000
SHA256          A705C0154FAFC7CD509DECF165CB6F6C050B6521B40ADB6F730DD827C86051C7
.text           RVA 0x00001000, raw 0x00000400, size 0x002D6800
.rdata          RVA 0x002D8000, raw 0x002D6C00, size 0x000EBE00
.data           RVA 0x003C4000, raw 0x003C2A00, size 0x0000A800
```

A patcher or script must refuse any other size or hash before writing.

The 30-site intermediate build has:

```text
size            6,517,616 bytes
SHA256          0D822AB317069F4B460A6B8333A26B56C8E527E080077212FB3E0209BD6CD395
```

That hash is the 30-site build: the base set in section 4, the tray and exit overlay in section 11, and the residual self-termination overlay in section 13.

The 30-site build still dies after 20 to 25 minutes. That death is not a header or timer problem: it is the crypt32 module unload race in section 14. Site 37 at file `0x478B1` removes one free and produces the intermediate 37-site build, but that build still crashes because the certificate path itself unloads `crypt32.dll`.

The current complete build is the inside build: the 30 code sites, site 37, the entry-point resident stub (site 38), the four inside dialog patches in section 15, and the PE `CheckSum` rewrite at file `0x150`.

```text
size            6,517,616 bytes
SHA256          199E459FCC1D4ECDFDF3649C8E708FEE5EEC07CA22BD5AA9C253077B11F3BC6D
```

The intermediate 37-site build (site 37 only, no resident stub) has:

```text
size            6,517,616 bytes
SHA256          3A63B29E905C24C823F19F25D27405B468FFC8092AD9C84BC8A4B1E4DC16D2B7
```

The 38-site base (30 sites, site 37, entry stub) has:

```text
size            6,517,616 bytes
SHA256          64BF39DD3BDD568389C84CF3546B4007B2B97775F728E485F670DFCBBF720DA0
```

The 39-site status-stub experiment (superseded by the inside build) has:

```text
size            6,517,616 bytes
SHA256          599B15C25C1B9F06DCC4049B88E332AA105BBC0C382423F86BEC0D15F2224085
```

The base plus tray set alone (22 sites) has:

```text
size            6,517,616 bytes
SHA256          BACF3DCC44073935FD72493A2578F0A7295FE2F447A9DCF68EC0C4CD3774A020
```

The 22-site build stops the buy page, the warnings and the update check but still closes itself after 180 seconds; ship the 30-site build.

### Helper reference build

```text
file            IDMGrHlp.exe
size            519,992 bytes
image base      0x00400000
SHA256          B3B6281EA820EAE8192E50B30698CF4C3B8BC3D4376C978403BC9E18E5857C23
.text           RVA 0x00001000, raw 0x00000400
```

The helper is a separate signed 32-bit MFC executable. It is launched by `IDMan.exe` and can also be started directly. It imports `MessageBoxA` at IAT `0x004434BC`.

## 3. License model

IDM stores four registration values:

```text
Serial   REG_SZ
FName    REG_SZ
LName    REG_SZ
Email    REG_SZ
```

At startup IDM opens `SOFTWARE\Internet Download Manager` under `HKLM`, and falls back to the already open `HKCU\Software\DownloadManager` key. The value name pointers are initialized at runtime:

| Global | Value name |
|---|---|
| `0x007D39C4` | `Serial` |
| `0x007D39C8` | `FName` |
| `0x007D39CC` | `LName` |
| `0x007D39D0` | `Email` |

The serial format is 23 characters:

```text
XXXXX-XXXXX-XXXXX-XXXXX
```

Hyphens are at zero-based positions 5, 11, and 17. The format check is in the registration loader around `0x004508D9`. Any syntactically valid synthetic serial passes the local format check. The registration status function then performs the local and online checks.

The registration status function is at `0x00450630`. It returns a code from 0 to 12. The caller at `0x0045250A` switches on that code through the jump table at `0x004534BC`:

| Status | Target | Effect |
|---:|---|---|
| 0 | `0x00452CB6` | registered or continue |
| 1 | `0x00452CCD` | counterfeit serial warning |
| 2 | `0x00452DD0` | blocked serial details |
| 3 | `0x00452E73` | counterfeit or blocked, IDM exits |
| 4 | `0x00452EAB` | trial with days left |
| 5 | `0x00452EFD` | exit |
| 6 | `0x00452EAB` | trial with days left |
| 7 | `0x00452E8F` | license expired |
| 8 | `0x00452EFD` | exit |
| 9 | `0x00452EFD` | exit |
| 10 | `0x00452CEC` | serial used on another computer |
| 11 | `0x00452EFD` | exit |
| 12 | `0x00452D0A` | exit |

The counterfeit return is at `0x0045181C`:

```text
B8 03 00 00 00   mov eax, 3
E9 ...           jmp 0x00450C88
```

Changing the immediate to 0 handles status 3 only. Statuses 1 and 2 still show the warning, and the certificate path is separate. The inside build keeps the original status function at `0x00450630` and suppresses the UI directly: the dialog procedure at `0x00651762` is redirected to a cave stub, the warning function at `0x00474760` returns 0, the licensed-to call at `0x00489FA6` is skipped, and the custom dialog wrapper call at `0x004A8B86` is skipped. See section 15. Use a random 5-5-5-5 serial, not the blacklisted `12345-67890-12345-67890`. Do not patch the `.data` flag at `0x007C4D24` to 0 in this build. That flag is the unregistered marker, and forcing it to 0 causes the registration dialog to open on startup even when the serial is present. Keep it at 1 and use the validator stubs and the section 15 patches instead.

## 4. Patch sites

All offsets below are file offsets in `IDMan.exe`. Convert a virtual address to a file offset with:

```text
file offset = virtual address - 0x00401000 + 0x00000400
```

Use section 16 for the exact build. The tables here and in sections 11, 13, 14 and 15 explain the sites; the script in section 16 is the execution path that reproduces the final hash. Do not apply the tables by hand unless you verify every byte and the final SHA256.

| Site | Virtual address | File offset | Original bytes | Patch bytes | Purpose |
|---|---:|---:|---|---|---|
| 1 | `0x00450BC4` | `0x0004FFC4` | `74 15` | `EB 15` | Force the online registration branch to success |
| 2 | `0x0045B0B0` | `0x0005A4B0` | `55 8B EC` | `B0 01 C3` | Name validator returns true |
| 3 | `0x0045B430` | `0x0005A830` | `55 8B EC` | `B0 01 C3` | Serial validator returns true |
| 4 | `0x0045181C` | `0x00050C1C` | `B8 03 00 00 00` | `B8 00 00 00 00` | Counterfeit status becomes 0 |
| 5 | `0x0049475F` | `0x00093B5F` | `E8 FC FF FD FF` | `31 C0 90 90 90` | Skip fake-serial warning 1 |
| 6 | `0x00475A84` | `0x00074E84` | `E8 D7 EC FF FF` | `31 C0 90 90 90` | Skip fake-serial warning 2 |
| 7 | `0x004569D0` | `0x00055DD0` | `55 8B EC` | `33 C0 C3` | Auto-update check returns 0 |
| 8 | `0x0047CDA0` | `0x0007C1A0` | `55` | `C3` | First buy-page builder returns immediately |
| 9 | `0x0047F643` | `0x0007EA43` | `E8 B8 7C 03 00` | `31 C0 90 90 90` | Skip the timer buy-page opener |
| 10 | `0x00486FE9` | `0x000863E9` | `0F 84 78 01 00 00` | `E9 79 01 00 00 90` | Force the timer's registered path |

### Site 1: online branch

`0x00450BC4` is a conditional jump after the online registration check. The original `74 15` jumps to the local success path when the check returns 0. Changing it to `EB 15` jumps unconditionally, so the online result cannot route the load into the counterfeit path.

### Sites 2 and 3: local validators

`0x0045B0B0` validates the registration name and `0x0045B430` validates the serial. Both are `cdecl` functions with one argument and are followed by `add esp, 4` at the call sites. Replacing the entry with:

```text
B0 01   mov al, 1
C3      ret
```

returns true without touching the argument stack. The caller cleans the argument.

### Site 4: counterfeit status

The status function returns 3 for a counterfeit serial. The switch at `0x00452535` sends status 3 to `0x00452E73`, which displays the counterfeit message and exits. Changing the `mov eax, 3` at `0x0045181C` to `mov eax, 0` sends the switch to the registered path.

### Sites 5 and 6: fake-serial warnings

Two separate paths display the fake-serial warning:

- `0x0049475F` in the download path, message text built on the stack around `0x004946E0`
- `0x00475A84` in the registration/status path, message text built around `0x00475A30`

Both call the message wrapper at `0x00474760`. Replacing each five-byte call with:

```text
31 C0         xor eax, eax
90 90 90      nop
```

removes the dialog without changing the surrounding control flow.

### Site 7: auto-update

`0x004569D0` reads `HKCU\Software\DownloadManager\LastCheckQU`, compares it with the current time, and returns 1 when an update check is due. Replacing the entry with:

```text
33 C0   xor eax, eax
C3      ret
```

makes the caller treat the check as not due. `LastCheckQU` stays unchanged after startup.

### Site 8: first buy page

`0x0047CDA0` builds the purchase URL from `https://secure%s/` and `%sbuy_idm.html?%s`, then opens it. It is called from `0x0053274F`. Replacing the first byte with `C3` returns immediately. The caller cleans the stack with `add esp, 0x14`, so the stack stays balanced. This removes the first automatic buy page and makes the in-app buy buttons inert.

### Site 9: timer buy-page opener

`0x0047F643` is a call to the URL opener at `0x004B7300` inside the timer path. The surrounding function builds `http://www.internetdownloadmanager.com/buy2.html` and opens it through Chrome. The caller pushes two arguments and cleans them with `add esp, 8` after the call. Replacing the five-byte call with:

```text
31 C0         xor eax, eax
90 90 90      nop
```

skips the URL open and keeps the stack balanced. The browser page and its redirect to `buy_idm2.html` no longer appear.

### Site 10: timer exit path

`0x00486FE9` is the conditional jump after the unregistered check in the timer handler:

```text
0x00486FE3   cmp dword [0x007C4D24], 0
0x00486FE9   0F 84 78 01 00 00   je 0x00487167
```

When the unregistered flag is 1, the timer writes `vCOUFP`, runs the trial path, and closes the application. Replacing the conditional jump with an unconditional jump:

```text
E9 79 01 00 00   jmp 0x00487167
90               nop
```

forces the registered path. IDM stays open after the timer fires. This is the patch that stops the complete application exit, not just the browser page.

## 5. Registry setup

Set the values before the first patched start:

```powershell
$key = 'HKCU:\Software\DownloadManager'
New-Item -Path $key -Force | Out-Null
Set-ItemProperty -Path $key -Name Serial -Value 'A7K2M-9Q4XZ-3V8NB-6T1WP'
Set-ItemProperty -Path $key -Name FName  -Value 'Test'
Set-ItemProperty -Path $key -Name LName  -Value 'User'
Set-ItemProperty -Path $key -Name Email  -Value 'test@example.com'
```

Use a synthetic serial. Do not use a leaked key. Do not use `12345-67890-12345-67890`; it is blacklisted and triggers the licensed-to path even with the section 15 patches.

Set the launched path as well:

```powershell
Set-ItemProperty -Path 'HKCU:\Software\DownloadManager' -Name ExePath -Value 'C:\Program Files (x86)\Internet Download Manager\IDMan.exe'
```

`ExePath` must equal the exact path of the running image. If it differs, IDMan exits in about 0.12 s with no window.

IDM may also read the values from `HKLM\SOFTWARE\WOW6432Node\Internet Download Manager`. The `HKCU` path is sufficient when the machine-wide key has no registration values.

## 6. Finding the sites in a new build

Skip this section for 6.43 build 18. The exact offsets for that build are in sections 4, 11, 13, 14 and 15. Use this section only when the installed version is different and the fixed offsets no longer match.

### 6.1 Strings and value names

Search the binary for:

```text
SOFTWARE\Internet Download Manager
Serial
FName
LName
Email
%sbuy_idm.html?%s%s
This feature is available in registered version only
has been registered with a counterfeit Serial Number
```

The `Serial`, `FName`, `LName`, and `Email` strings are UTF-16 in `.rdata`. The value-name pointers are initialized in the startup string builder around `0x004ED31D` and `0x0052E1C0`. At runtime the pointers at `0x007D39C4`, `0x007D39C8`, `0x007D39CC`, and `0x007D39D0` resolve to those names. Read them from a running process with `ReadProcessMemory` if the build moves.

### 6.2 Status function and switch

Find the function that returns a small status code and is followed by a jump table:

```text
cmp eax, 0x0C
ja  ...
jmp dword [eax*4 + <table>]
```

In 6.43 build 18 the function starts at `0x00450630`, the switch is at `0x00452535`, and the table is at `0x004534BC`. The counterfeit case is the table entry that points to a block containing the counterfeit message. In this build that is entry 3 and the handler is `0x00452E73`. Find the `mov eax, 3` immediately before the jump to the common epilogue and change it to 0.

Do not patch the `.data` flag at `0x007C4D24` as a shortcut. In this build it is the unregistered marker and forcing it to 0 produces a registration prompt.

### 6.3 Validators

The two local validators are reached from the registration dialog and the About dialog:

```text
0x0048E1CE  call 0x0045B0B0   ; name
0x0048E1E1  call 0x0045B430   ; serial
0x0046C34D  call 0x0045B430
0x0046C445  call 0x0045B0B0
0x0046C4B5  call 0x0045B430
```

Find the functions that are called with the `FName` and `Serial` buffers and replace their entries with `B0 01 C3`.

### 6.4 Warning call sites

Find `call 0x00474760` followed by `add esp, 0x10` in the registration and download code. In 6.43 build 18 the two warning sites are `0x0049475F` and `0x00475A84`. The message text is built on the stack from encrypted byte stores, so a plain string search will not find the final sentence. Use a debugger breakpoint on `MessageBoxW` and a backtrace to the `call 0x00474760` site instead.

### 6.5 Buy page

Search for `%sbuy_idm.html?%s` and `%sbuy1.html?%s`. The builder in 6.43 build 18 starts at `0x0047CDA0` and is called from `0x0053274F`. Find the function that formats `https://secure%s/` and patch its entry to return.

### 6.6 Auto-update

Search for `LastCheckQU` and `IDMGrHlp.exe`. The check function in 6.43 build 18 starts at `0x004569D0`. It returns 1 when the last check is older than six days. Replace the entry with `33 C0 C3`.

## 7. Verification

### Desktop

- Start `IDMan.exe`.
- Read `HKCU\Software\DownloadManager\idmvers`. It must change from `v6.43b18 Trial` to `v6.43b18 Full`.
- Open the About dialog. It must not show a trial counter.
- Add a download. No counterfeit dialog and no fake-serial warning may appear.
- Confirm that no `buy_idm2.html` page opens in the browser.
- Read `LastCheckQU` before and after startup. It must not change.
- Let a small download complete and compare its size with the server.
- Confirm `Crypt32.dll` is in the 32-bit module list immediately after launch.
- Open the Registration dialog. No registration window, no counterfeit warning, and no licensed-to message may appear.
- Wait at least 25 minutes in the tray, not 90 seconds. The process must stay alive, `Crypt32.dll` must stay in the module list, and no `buy2.html` or `buy_idm2.html` browser process may appear.

The 90-second test only covers the base overlay. The inside build needs the 25 minute check in 14.7; the old 20 to 25 minute failure is the crypt32 race.

### IDMGrHlp helper

- Run `IDMGrHlp.exe` directly. It must exit with code 0 and show no window.
- Start `IDMan.exe` and wait at least six minutes. No "fake Serial Number" dialog may appear.
- `Get-Process IDMGrHlp` must not show a `MainWindowTitle` of `Internet Download Manager`.

### Patch verification

Re-read every site after writing:

```text
0x4FFC4  EB 15
0x5A4B0  B0 01 C3
0x5A830  B0 01 C3
0x50C1C  B8 00 00 00 00
0x93B5F  31 C0 90 90 90
0x74E84  31 C0 90 90 90
0x55DD0  33 C0 C3
0x7C1A0  C3
0x7EA43  31 C0 90 90 90
0x863E9  E9 79 01 00 00 90
```

`IDMGrHlp.exe`:

```text
0x52A1  31 C0 90 90 90 90
0x52C8  31 C0 90 90 90 90
```

The block above lists the base sites only. The complete inside manifest is the `PATCHES` list in section 16. The key extra assertions for the inside build are:

```text
0x120    4C 76 2D 00
0x150    F7 B6 63 00
0x478B1  90 90 90 90 90 90 90
0x2D6A4C E8 00 00 00 00 58 2D 51 76 2D 00 89 C3 60 8D 83 88 F8 30 00 50 8B 93 EC 83 2D 00 FF D2 61 E9 7D D7 FA FF
0x2D6A80 8B FF 55 8B EC 81 7D 0C 10 01 00 00 0F 85 D5 A0 F7 FF 60 E8 00 00 00 00 5B 81 EB 98 76 2D 00 8B 75 08 56 8B 83 E4 87 2D 00 FF D0 83 F8 26 75 19 6A 00 6A 00 6A 10 56 8B 83 E8 87 2D 00 FF D0 61 B8 01 00 00 00 5D C2 10 00 61 E9 98 A0 F7 FF
0x250B62 E9 19 5F 08 00
0x73B60  31 C0 C3
0x893A6  31 C0 90 90 90
0xA7F86  31 C0 90 90 90 90
0x4FA30  55 8D AC
```

After the base set only (section 4, 22 sites with the tray overlay), the SHA256 of the patched file is:

```text
BACF3DCC44073935FD72493A2578F0A7295FE2F447A9DCF68EC0C4CD3774A020
```

After site 37 only (sections 4, 11 and 13, plus site 37 and the checksum), the SHA256 is the intermediate 37-site build:

```text
3A63B29E905C24C823F19F25D27405B468FFC8092AD9C84BC8A4B1E4DC16D2B7
```

After the complete inside set (site 37, site 38 resident stub, sites 40 to 43 and the checksum), the SHA256 is:

```text
199E459FCC1D4ECDFDF3649C8E708FEE5EEC07CA22BD5AA9C253077B11F3BC6D
```

The SHA256 of the patched helper must be:

```text
F5E7360A0C376247507218AC92392BD8B71AF70376E3BF1058C77AFED575B36D
```

Any other hash means the patch set, order, or target build is wrong.

## 8. Rollback

1. Close `IDMan.exe` and `IDMGrHlp.exe`.
2. Restore the pristine `IDMan.exe` and `IDMGrHlp.exe` from the backup outside the install directory.
3. Delete `Serial`, `FName`, `LName`, and `Email` under `HKCU\Software\DownloadManager`.
4. Start IDM and confirm the trial state returns.

The pristine backup must be kept outside `%ProgramFiles(x86)%\Internet Download Manager` so an update or a media build cannot embed it. Intermediate and complete backups are listed in 14.8.

## 9. Packaging and distribution

Do not commit the patched `IDMan.exe`, a keygen, or a compiled patcher to a public or private repository. Distributing a ready-to-run circumvention binary can trigger a DMCA notice and repository removal, and private repositories are not immune to a valid notice.

Commit only this playbook, the project README, and local build notes. If a patcher is needed, build it locally and keep the binary outside the repository.

## 10. Notes

- The serial format check is not a license check. Any syntactically valid synthetic serial passes the local format stage.
- The online branch and the counterfeit status are separate. Patching only one of them leaves either the exit dialog or the warning path active.
- The two warning call sites are independent. Patching only one leaves the other message visible. The section 15 patches make both unreachable and stop the licensed-to dialog as well.
- The 20 to 25 minute disappearance is the crypt32 reference-counted unload. Site 37 removes one free, but the certificate path unloads the module anyway. Site 38 holds a permanent reference at the entry point.
- The registration status function is at `0x00450630` and has one caller at `0x0045250A`. The inside build leaves it original and suppresses the UI through the section 15 dialog procedure, warning function, licensed-to call and wrapper call.
- The first buy-page builder at `0x0047CDA0` and the timer buy-page opener at `0x0047F643` are separate. Patching only the builder leaves the startup buy page and the timer exit active.
- The timer exit is controlled by the unregistered check at `0x00486FE9`. The buy-page opener alone does not stop the application close.
- `LastCheckQU` is a timestamp, not a boolean. Do not set it to a far-future value as the only update fix; patch the check function instead.
- IDM replaces `IDMan.exe` on update. Re-run the discovery workflow after every update.
- The registry values are per-user. A new Windows profile needs the five values again, including `ExePath`.
- `IDMGrHlp.exe` is a separate signed helper. Its two fake-serial dialogs are not suppressed by any `IDMan.exe` patch. Patch the helper at file offsets `0x52A1` and `0x52C8`.

## 11. Tray and exit overlay

The base ten patches stop the buy page, the fake-serial warnings, and the update check. They do not stop the timer that closes the application after it hides to the tray, and they do not stop the timer that launches the second purchase URL. Apply this overlay after the base set.

| Site | File offset | Original bytes | Patch bytes | Purpose |
|---|---:|---|---|---|
| 11 | `0x000914DD` | `FF 15 44 E5 7C 00` | `E8 A5 13 03 00 90` | Replace the timer `ShellExecuteA` call with a `ret 0x18` gadget |
| 12 | `0x00088C15` | `8B 75 08 8B C6` | `E9 DA 0A 00 00` | Redirect `WM_CLOSE` to the hide-to-tray cave |
| 13 | `0x000896F4` | `CC` x 34 | cave code | Hide the window and return 0 on `WM_CLOSE` |
| 14 | `0x0008DA76` | `68 10 27 00 00` | `68 FF FF FF 7F` | Disable the 10 second exit timer |
| 15 | `0x0006C073` | `8D 8E 20 4E 00 00 51` | `68 FF FF FF 7F 90 90` | Disable the 32 second exit timer |
| 16 | `0x0006C08C` | `75 41` | `90 90` | Remove the timer exit branch |
| 17 | `0x0006C09A` | `E8 B1 72 FB FF` | `83 C4 0C 90 90` | Skip the 12 second registration timer |
| 18 | `0x000101D4` | `FF 15 04 85 6D 00` | `E8 06 05 FF FF 90` | Neutralize the first stray `ExitProcess` call |
| 19 | `0x0004D006` | `FF 15 04 85 6D 00` | `E8 D4 36 FB FF 90` | Neutralize the second stray `ExitProcess` call |
| 20 | `0x0006640B` | `FF 15 04 85 6D 00` | `E8 CF A2 F9 FF 90` | Neutralize the third stray `ExitProcess` call |
| 21 | `0x0006C0CF` | `FF 15 04 85 6D 00` | `E8 0B 46 F9 FF 90` | Neutralize the fourth stray `ExitProcess` call |
| 22 | `0x00120D5C` | `FF 15 04 85 6D 00` | `E8 7E F9 ED FF 90` | Neutralize the fifth stray `ExitProcess` call |

The cave at `0x48A2F4` (`0x000896F4`) is:

```text
8B 75 08             mov esi, [ebp+8]
83 FE 10             cmp esi, 0x10
74 0A                je close
8B C6                mov eax, esi
83 E8 01             sub eax, 1
E9 17 F5 FF FF       jmp 0x48981D
6A 00                push 0
FF 77 20             push dword [edi+0x20]
FF 15 DC 87 6D 00    call dword [0x6D87DC]
E9 34 F5 FF FF       jmp 0x48984A
```

`ShowWindow` is imported at `0x006D87DC`. The cave returns through the normal function epilogue at `0x0048984A`, so the SEH frame and stack stay balanced.

### 11.1 Why the overlay is required

The first buy-page block is at `0x004920AA` in the timer handler. It builds the URL and calls `ShellExecuteA` at `0x004920DD`. Replacing that call with a call to a `ret 0x18` gadget removes the browser launch without leaving six arguments on the stack.

The `WM_CLOSE` message is not handled by the main window procedure. It falls through to `DefWindowProc`, which destroys the window and ends the message loop. Patch 12 intercepts `WM_CLOSE` before the message switch and sends it to the cave. The cave hides the window and returns 0, so the window remains alive in the tray.

The application still exits later because the registration timer calls `ExitProcess` at `0x0046CCCF`. Timer 4 fires after 10 seconds, timer 1 after about 32 seconds, and timer 111 after about 12 seconds. The timer overlay disables all three and neutralizes the five application `ExitProcess` calls, so a stray timer cannot terminate the process.

### 11.2 Verification

- Start `IDMan.exe`. Wait 45 seconds. The process must remain alive.
- Send `WM_CLOSE` to the main window. The window must become hidden, and the process must remain alive for at least 20 seconds.
- Confirm that the tray icon is present in the notification area.
- Confirm that no `buy2.html` or `buy_idm2.html` browser process appears.
- Confirm that the patched SHA256 is:

```text
BACF3DCC44073935FD72493A2578F0A7295FE2F447A9DCF68EC0C4CD3774A020
```

## 12. IDMGrHlp fake-serial dialogs

`IDMGrHlp.exe` is the helper that shows the two fake-serial dialogs every five minutes. The dialogs are not produced by `IDMan.exe`, so the base and tray patches do not stop them. The helper imports `MessageBoxA` at IAT `0x004434BC` and calls it twice in the fake-serial check.

| Site | Virtual address | File offset | Original bytes | Patch bytes | Purpose |
|---|---:|---:|---|---|---|
| 23 | `0x00405EA1` | `0x000052A1` | `FF 15 BC 34 44 00` | `31 C0 90 90 90 90` | Suppress the short `MB_OK` warning |
| 24 | `0x00405EC8` | `0x000052C8` | `FF 15 BC 34 44 00` | `31 C0 90 90 90 90` | Suppress the long `MB_OKCANCEL` warning |

The first call is the short `MB_OK | MB_ICONWARNING | MB_SYSTEMMODAL` dialog, flags `0x1030`. The second call is the long `MB_OKCANCEL | MB_ICONWARNING | MB_SYSTEMMODAL` dialog, flags `0x1031`. The long dialog's OK branch builds an encrypted URL and calls `ShellExecuteA` at `0x0040605D`. Replacing each six-byte `call dword [0x004434BC]` with:

```text
31 C0         xor eax, eax
90 90 90 90   nop
```

returns 0, takes the no-URL branch, and lets the helper exit with code 0. The second dialog no longer has an OK path that can reach the browser.

The helper is Authenticode-signed. The patch invalidates the signature. A direct shell launch may be refused; start it from IDM's normal path or with `UseShellExecute = $false`.

### 12.1 Verification

- Run `IDMGrHlp.exe` directly. It must exit with code 0 and show no window.
- Start `IDMan.exe` and wait at least six minutes. No fake-serial dialog may appear.
- `Get-Process IDMGrHlp` must not show `MainWindowTitle = Internet Download Manager`.
- The patched helper SHA256 must be:

```text
F5E7360A0C376247507218AC92392BD8B71AF70376E3BF1058C77AFED575B36D
```

### 12.2 Helper patch script

Run this on a pristine `IDMGrHlp.exe` with SHA256 `B3B6281EA820EAE8192E50B30698CF4C3B8BC3D4376C978403BC9E18E5857C23`. The installed helper may already be patched; the assertion will fail in that case, which is the correct behavior.

```python
import hashlib

src = r"IDMGrHlp.exe"
dst = r"IDMGrHlp.patched.exe"
b = bytearray(open(src, "rb").read())
assert len(b) == 519992
assert hashlib.sha256(b).hexdigest().upper() == "B3B6281EA820EAE8192E50B30698CF4C3B8BC3D4376C978403BC9E18E5857C23"
for off in (0x52A1, 0x52C8):
    b[off:off+6] = bytes.fromhex("31 C0 90 90 90 90")
open(dst, "wb").write(b)
print(hashlib.sha256(b).hexdigest().upper())
```

Expected output:

```text
F5E7360A0C376247507218AC92392BD8B71AF70376E3BF1058C77AFED575B36D
```

## 13. Residual self-termination overlay (30-site build)

The 22-site build still closed itself after 180.3 seconds with no user action. This section documents the trigger, the terminal path, the eight added sites, and the verification. Apply this overlay after the base set in section 4 and the tray and exit overlay in section 11. This produces the 30-site intermediate. Sections 14 and 15 extend it to the inside build.

### 13.1 Measured failure of the 22-site build

| Run | Trigger | Observed |
|---|---|---|
| baseline, pid 33216 | none, window visible | process gone at t=180.3 s, exit code `-1` (0xFFFFFFFF) |

Short 90-second tests pass on the 22-site build, which is why the base verification in section 7 missed it. The death needs more than three minutes of idle time.

### 13.2 Trigger: timer ID 0x15 at 180000 ms

`SetTimer` is called with a 180000 ms elapse at two sites that the 22 sites never touched:

```text
0x00477665  68 20 BF 02 00   push 0x2BF20
0x0047766A  6A 15            push 0x15        ; timer id 21
0x0047766C  8B 4E 20         mov ecx, [esi+0x20]
0x0047766F  51               push ecx
0x00477670  FF D7            call edi         ; SetTimer

0x0048E65C  68 20 BF 02 00   push 0x2BF20
0x0048E661  6A 15            push 0x15
0x0048E663  8B 4B 20         mov ecx, [ebx+0x20]
0x0048E666  51               push ecx
0x0048E667  FF D6            call esi         ; SetTimer
```

Timer 21 is the only 180-second timer in the image, which matches the measured 180.3 s death. Site 14 in section 11 disabled the 10-second twin in the same initializer and left this arm running.

### 13.3 Terminal path: PostQuitMessage ends the message loop

```text
WM_DESTROY in the tray controller window procedure 0x0054F4A0
  0x0054F500  6A 00                  push 0
  0x0054F502  FF 15 5C 86 6D 00      call dword [0x006D865C]   ; PostQuitMessage(0)
GetMessage returns 0, the message loop ends, WinMain returns
CRT exit() calls ExitProcess at 0x00680087 (file 0x0027F487)
```

None of the five `ExitProcess` sites patched by sites 18 to 22 is on this path, and the CRT site cannot be patched in isolation because returning from it resumes CRT teardown. The fix sits upstream: disable the 180-second timer and neutralize the four direct `PostQuitMessage` call sites, so no window destruction can end the loop.

### 13.4 Added sites

All offsets are file offsets in `IDMan.exe`. The starting point is the 22-site build `BACF3DCC...`.

| Site | File offset | Virtual address | Original bytes | Patch bytes | Purpose |
|---:|---:|---:|---|---|---|
| 23 | `0x00076665` | `0x00477665` | `68 20 BF 02 00` | `68 FF FF FF 7F` | Timer 21 arm A becomes INFINITE |
| 24 | `0x0008DA5C` | `0x0048E65C` | `68 20 BF 02 00` | `68 FF FF FF 7F` | Timer 21 arm B becomes INFINITE |
| 25 | `0x0014E902` | `0x0054F502` | `FF 15 5C 86 6D 00` | `58 90 90 90 90 90` | Tray `WM_DESTROY` no longer posts `WM_QUIT` |
| 26 | `0x000B7E27` | `0x004B8A27` | `FF 15 5C 86 6D 00` | `58 90 90 90 90 90` | Second `PostQuitMessage` site |
| 27 | `0x000E21BE` | `0x004E21BE` | `FF 15 5C 86 6D 00` | `58 90 90 90 90 90` | Third `PostQuitMessage` site |
| 28 | `0x000E2647` | `0x004E2647` | `FF 15 5C 86 6D 00` | `58 90 90 90 90 90` | Fourth `PostQuitMessage` site |
| 29 | `0x000101DA` | `0x00410DDA` | `CC` | `C3` | Site 18 return lands on `int3` padding, return to caller instead |
| 30 | `0x0025F5A0` | `0x0065F5A0` | `FF 25 5C 86 6D 00` | `C3 90 90 90 90 90` | Unused tail-jump thunk to `PostQuitMessage` becomes `ret` |

Site 30 removes the last reference to the `PostQuitMessage` IAT slot. It is a six-byte `jmp dword [0x006D865C]` tail thunk that no `call` targets after sites 25 to 28 are patched. A bare `ret` returns to its caller with the stack unchanged, which is correct for a tail jump.

### 13.5 Why the patch is stack neutral

Sites 23 and 24 keep the `push imm32` instruction shape. The elapse becomes `0x7FFFFFFF` (2147483647 ms, about 24.8 days), the same value sites 14 and 15 use. `SetTimer` is still called with four arguments, so the stack is byte identical to the original.

Sites 25 to 28 replace the six-byte `call dword [0x6D865C]` with `pop eax` plus five NOPs. The preceding `push 0` (sites 25, 26, 27) or `push ebx` (site 28) already placed the argument; `pop eax` removes exactly that dword, so the stack depth, return address and SEH chain after the site are the same as before it. No cave is used and no return address is touched.

Site 29 changes one padding byte from `CC` to `C3`, with no stack effect. Site 18 replaces `call dword [ExitProcess]` with `call 0x004012DF`, and that gadget is `ret 4`: it pops the pushed exit code and returns to the byte after the call, which in the pristine image is `CC`. If that path is reached, the process raises `STATUS_BREAKPOINT`; `C3` makes it return to the caller instead.

None of the eight sites overlaps sites 1 to 22 or the cave at `0x000896F4`. The cave ends at `0x00089716`.

### 13.6 Verification

```text
pristine          A705C0154FAFC7CD509DECF165CB6F6C050B6521B40ADB6F730DD827C86051C7
22-site           BACF3DCC44073935FD72493A2578F0A7295FE2F447A9DCF68EC0C4CD3774A020
30-site           0D822AB317069F4B460A6B8333A26B56C8E527E080077212FB3E0209BD6CD395
```

Sections 14 and 15 extend this build to the inside image, SHA256 `199E459FCC1D4ECDFDF3649C8E708FEE5EEC07CA22BD5AA9C253077B11F3BC6D`. See sections 14.5 and 16.

Byte assertions after writing:

```text
0x76665  68 FF FF FF 7F
0x8DA5C  68 FF FF FF 7F
0x14E902 58 90 90 90 90 90
0xB7E27  58 90 90 90 90 90
0xE21BE  58 90 90 90 90 90
0xE2647  58 90 90 90 90 90
0x101DA  C3
0x25F5A0 C3 90 90 90 90 90
```

Live test:

1. Start `IDMan.exe`. Do not touch it.
2. Leave the window visible for at least 200 seconds. The process must stay alive past the 180-second mark.
3. Send `WM_CLOSE` to the main window. The window must become hidden and the process must stay alive.
4. Poll every 10 seconds for at least 30 minutes. The process must remain alive, the tray icon must be present, no `buy2.html` or `buy_idm2.html` browser process may appear, and no fake-serial dialog may appear.
5. Kill the test instance when the run ends.

The 30-site build was also soaked with the overlay applied to a running process in memory, which is the same code path without touching the installed file. It remained alive past 180 seconds and through the rest of the run; see the work-directory log for the exact timing.

### 13.7 Rollback

1. Close `IDMan.exe` and `IDMGrHlp.exe`.
2. Restore the 22-site `IDMan.exe` (SHA256 `BACF3DCC...`) or the pristine build (SHA256 `A705C015...`) from the backup outside the install directory.
3. Leave the registry values in place; they are not modified by this overlay.

The eight sites are additive. Reverting them is enough to return to the 22-site behavior, because none of them shares bytes with sites 1 to 22.

### 13.8 Notes

- The 180-second timer is armed from two places. Patching only one leaves the other live; that was the defect in the first 29-site attempt.
- The four `PostQuitMessage` sites are independent. Any one of them can end the loop, so all four are patched.
- The tail-jump thunk at `0x0025F5A0` is patched to `ret` so no reference to the `PostQuitMessage` IAT slot remains. It has no `call` targets after sites 25 to 28, and a bare `ret` there returns with the stack unchanged.
- Four 20-minute timers exist (`push 0x124F80`, timer IDs 0x25, 0x2B, 0x2F). They are not exit paths. The four case bodies contain no process-kill primitive, and full install-dir copies with all four intervals shortened to 10 seconds survived six firings and more. The exit is the crypto module unload race in section 14, not a timer path.
- `IDMGrHlp.exe` is a separate signed helper. Its two fake-serial dialogs are suppressed by section 12; the helper does not terminate `IDMan.exe` and does not need the timer overlay.
- IDM replaces `IDMan.exe` on update. Re-run the discovery workflow after every update, apply all sites including site 37, then recompute the PE checksum in section 14.

## 14. Crypto module unload race (the real exit)

### 14.1 Symptom

`IDMan.exe` disappears without a dialog and without a buy page. The tray icon goes with it. The delay is not a fixed 20 minutes: measured uptime at death across nine Windows Error Reporting records ranges from 33 seconds to 47 minutes. The 20 to 25 minute window is the common cluster, not a timer. On 2026-11-14 a 31-site build sitting in the tray died 125 seconds after launch, and the same fault signature appeared.

Tray state correlates with the reported deaths. The crash site is the certificate chain engine, which IDM reaches from background network work that can run while the window is hidden. Tray state is not a requirement of the fault: one recorded death happened 33 seconds after launch.

### 14.2 Fault signature

Every death is the same record:

```text
Faulting application name: IDMan.exe, version: 6.43.18.2
Faulting module name: CRYPT32.dll_unloaded, version: 10.0.26100.9549
Exception code: 0xc0000005
Fault offset: 0x0005d220
```

`CRYPT32.dll_unloaded` means the faulting instruction pointer lies inside a module that has already been unmapped. The offset is not an export. In this crypt32 build `CertFindChainInStore` is at RVA `0xA8C90` and `CertFreeCertificateChainEngine` at `0x5D620`; `0x5D220` falls between `I_CertProtectFunction` (`0x5B9D0`) and `CertFreeCertificateChainEngine`, inside the chain engine. The thread was executing there when the module was pulled out from under it.

Measured uptime at death (Event 1000 start time is UTC, local time is UTC+2):

| Fault time (local) | PID | Uptime | Build |
|---|---:|---:|---|
| 2026-11-14 01:38:13 | 7724 | 125 s | 31-site |
| 2026-11-14 01:25:34 | 26192 | 616 s | 35-site |
| 2026-11-13 19:16:31 | 30072 | 371 s | installed |
| 2026-11-13 18:07:03 | 23416 | 139 s | temp copy |
| 2026-11-13 17:50:48 | 20756 | 33 s | installed |
| 2026-11-13 15:03:11 | 20304 | 1291 s | installed |
| 2026-11-13 13:36:39 | 32248 | 594 s | installed |
| 2026-11-13 13:02:05 | 25524 | 1680 s | installed |
| 2026-11-12 22:10:01 | 28212 | 2808 s | installed |

### 14.3 Mechanism

IDM loads crypt32 itself and caches both the module handle and one resolved pointer:

| Step | VA | Bytes | Effect |
|---|---:|---|---|
| load name | `0x70F888` | UTF-16 `Crypt32.dll` | module name string |
| load call | `0x5EF4D2` | `68 88 F8 70 00` / `E8 ...` | push name, call loader wrapper `0x446A00` |
| LoadLibraryW | `0x446A28` | `8B 2D EC 83 6D 00` | wrapper resolves `LoadLibraryW` from IAT `0x6D83EC` |
| cache handle | `0x5EF4DF` | `A3 64 20 7D 00` | store handle at `[0x7D2064]` |
| resolve | `0x5EF4EE` | `FF 15 E0 84 6D 00` | `GetProcAddress(handle, "CertFindChainInStore")` |
| cache pointer | `0x5EF4F4` | `A3 BC 3E 7D 00` | store pointer at `[0x7D3EBC]` |

The name string for the resolve is at VA `0x721CEC` (plain ASCII `CertFindChainInStore`).

The teardown path frees that handle but leaves both caches populated:

| Step | VA | Bytes | Effect |
|---|---:|---|---|
| load handle | `0x4484A8` | `A1 64 20 7D 00` | `mov eax, [0x7D2064]` |
| test | `0x4484AD` | `85 C0` / `74 07` | skip if zero |
| free | `0x4484B1` | `50 FF 15 C0 84 6D 00` | `push eax` / `call [0x6D84C0]` (`FreeLibrary`) |
| no zeroing | `0x4484B8` | `A1 E8 20 7D 00` | next field; `[0x7D2064]` keeps the dead handle |

Two failures follow from those bytes. A worker thread already inside the chain engine is unmapped by the `FreeLibrary`, which produces the `0x5D220` fault. If any later code reaches the chain path again, `[0x7D2064]` is non-zero so the loader branch is skipped, and `[0x7D3EBC]` still points into the unloaded module. The cache outlives the module either way. This destructor is one unload source; section 14.11 documents the reference-counted unload from the certificate path.

The two sides of the race have exact call sites. The chain build is an indirect call through the cached pointer at `0x5EF517` (`FF D0`), with six arguments pushed at `0x5EF50A..0x5EF516`; this is the call that is executing when the module disappears. The teardown is reached from the deleting destructor at `0x4486D0` (`push esi` / `mov esi, ecx` / `call 0x4483A0`), which enters the cleanup at `0x448459` and reaches the `FreeLibrary` at `0x4484B2`.

The 20-minute timers are not involved. The four `0x124F80` arms (`0x477286`, `0x48745D`, `0x48F21C`, `0x49A076`) and the 10-minute `0x927C0` arm (`0x4874B9`) all feed the license nag at `0x48735E`: `KillTimer(0x25)`, clear the latch at `[esi+0x290]`, compare `[eax+0x3DC]` against `0x5E3`/`0x5BB`/`0x5A6`/`0x595`, send `WM_COMMAND` `0x1518`/`0x14EC`/`0x14DD`/`0x14BC`, or re-arm. No kill primitive appears in that body.

### 14.4 Site 37: one free removed, not sufficient

Site 37 removes the destructor free at `0x4484B2`. It does not stop the certificate path from unloading `crypt32.dll`, so a build with site 37 alone still dies.

| Site | File offset | Original bytes | Patch bytes | VA | Purpose |
|---|---:|---|---|---:|---|
| 37 | `0x478B1` | `50 FF 15 C0 84 6D 00` | `90 90 90 90 90 90 90` | `0x4484B1` | drop `push eax` and `call [FreeLibrary]` in the object destructor |

The seven bytes are self-contained. `0x4484B1` is `push eax`, `0x4484B2` is `call dword [0x6D84C0]`, and `0x4484B8` begins `mov eax, [0x7D20E8]`, so the replacement ends exactly on the next instruction boundary. NOPing the push along with the call keeps the stack neutral.

Site 37 is kept because it removes a real double-free source, but it is not the fix. The evidence is in 14.11: the installed 37-site build crashed at 10:45:54 with the same `CRYPT32.dll_unloaded` record, and a Frida trace of the fixed process showed `LdrUnloadDll` called on the crypt32 base from the certificate path while the cached pointer at `[0x7D3EBC]` stayed non-zero.

### 14.5 Site 31: PE checksum hygiene

Recompute the optional header checksum after site 37 and write it at file `0x150`. This field is not the cause of the exit. The 31-site build had a correct checksum and still died at `crypt32+0x5D220`; the user-mode loader does not verify `CheckSum` for an exe, and this binary imports no `imagehlp` or `wintrust` function. Site 31 is kept because the header should describe the file.

| Build | File | Stored CheckSum | Computed | Match |
|---|---|---:|---:|---|
| pristine | `revert_pristine.exe` | `0x006455C4` | `0x006455C4` | yes |
| 30-site | `backup\IDMan.exe.installed` | `0x006455C4` | `0x0063AF39` | no |
| 31-site | install, before site 37 | `0x0063AF39` | `0x0063AF39` | yes |
| 37-site | `runs\cryptfix\IDMan.exe` | `0x006405BE` | `0x006405BE` | yes |
| 38-site | `runs\IDMan.resident.exe` | `0x0063EBB5` | `0x0063EBB5` | yes |
| 39-site | `runs\IDMan.resident2.exe` | `0x00641EA8` | `0x00641EA8` | yes |
| inside | `runs\IDMan.inside3.exe` | `0x0063B6F7` | `0x0063B6F7` | yes |

The 38-site build adds the entry stub to the 37-site build and has SHA256 `64BF39DD3BDD568389C84CF3546B4007B2B97775F728E485F670DFCBBF720DA0`. The 39-site build adds the registration status stub and has SHA256 `599B15C25C1B9F06DCC4049B88E332AA105BBC0C382423F86BEC0D15F2224085`; it is superseded by the inside build. The inside build adds the section 15 dialog patches and has SHA256 `199E459FCC1D4ECDFDF3649C8E708FEE5EEC07CA22BD5AA9C253077B11F3BC6D`.

The value changes when the code changes. Recompute it for every build; never copy a checksum from another build.

### 14.6 Procedure

1. Close `IDMan.exe` and `IDMGrHlp.exe`. Confirm no `IDMan.exe` process remains.
2. Back up the current installed `IDMan.exe` outside the install directory.
3. Apply the 30 sites from sections 4, 11 and 13.
4. Apply site 37 at file `0x478B1`.
5. Apply site 38: write the entry stub at file `0x2D6A4C` and set `AddressOfEntryPoint` to RVA `0x2D764C` (VA `0x6D764C`). The stub bytes are in 14.12.
6. Apply the section 15 patches: site 40 dialog procedure jump, the 79-byte cave at file `0x2D6A80`, site 41 warning function, site 42 licensed-to call, and site 43 dialog wrapper call.
7. Recompute the PE checksum and write it at file `0x150`, last.
8. Read back the bytes and both checksum values, and confirm `stored == computed`.
9. Write the result to the install directory (requires elevation on a default install).
10. Set `HKCU\Software\DownloadManager\ExePath` to `C:\Program Files (x86)\Internet Download Manager\IDMan.exe`.
11. Start IDM once and confirm `crypt32.dll` is in the 32-bit module list immediately, before any download. That proves the entry stub ran.
12. Open the Registration dialog. No registration window, no fake-serial warning, and no licensed-to message may appear.
13. Run one download. Only the standard `Download File Info` and `Download complete` windows may appear.
14. Close the main window to the tray and leave it hidden for 40 minutes.

### 14.7 Verification

- File size is `6,517,616` bytes.
- File `0x478B1..0x478B7` is `90 90 90 90 90 90 90`.
- `AddressOfEntryPoint` is `0x2D764C` (VA `0x6D764C`). File `0x2D6A4C..0x2D6A6E` holds the 35-byte stub in 14.12.
- File `0x4FA30..0x4FA32` is `55 8D AC` (the original status function).
- File `0x2D6A80..0x2D6ACE` holds the 79-byte dialog stub. File `0x250B62` is `E9 19 5F 08 00`.
- File `0x73B60` is `31 C0 C3`; file `0x893A6` is `31 C0 90 90 90`; file `0xA7F86` is `31 C0 90 90 90 90`.
- File `0x150` holds the checksum of the final file, stored value equals computed value.
- Build hash for the exact inside patch set is `199E459FCC1D4ECDFDF3649C8E708FEE5EEC07CA22BD5AA9C253077B11F3BC6D`.
- `crypt32.dll` is in the 32-bit module list immediately after launch, before any download. The entry stub at `0x6D764C` ran and holds one reference.
- Trigger one HTTPS transfer. The certificate path calls `LdrUnloadDll` on the crypt32 base (observed at 11:22:37 in the Frida trace). Immediately after that call, `crypt32.dll` is still in the module list and every later sample still shows it. The reference from site 38 absorbed the unload, so the cached pointer at `[0x7D3EBC]` stays valid.
- A 64-bit PowerShell module enumeration sees only the WOW64 host modules. Use a 32-bit Toolhelp32 enumerator (`CreateToolhelp32Snapshot` with `TH32CS_SNAPMODULE32`) for every sample.
- Opening `WM_COMMAND 32783` (Registration) produces no `Internet Download Manager Registration` window, no fake-serial warning, and no licensed-to message. The dialog procedure stub closes the title length 38 dialog, and the warning and licensed-to functions are bypassed.
- A normal download shows only the standard `Download File Info` and `Download complete` windows.
- After the soak, the process is alive and no Application Error 1000 record for that pid carries fault offset `0x0005d220`.
- A clean 40-minute run is a regression check. The direct evidence is the module-presence observation after an `LdrUnloadDll` call, not survival alone.

### 14.8 Rollback

Close IDM, restore a backup over `IDMan.exe`, and set `ExePath` back to the install path if it was changed. Recompute nothing. Available backups:

- pristine `IDMan.exe` (`A705C0154FAFC7CD509DECF165CB6F6C050B6521B40ADB6F730DD827C86051C7`)
- 30-site `IDMan.exe` (`0D822AB317069F4B460A6B8333A26B56C8E527E080077212FB3E0209BD6CD395`)
- 31-site `IDMan.exe` (`2B873DAE7A2F9438BD847816F44FBBA130E06998C134535EC6B80B97928608A6`)
- 37-site `IDMan.exe` (`3A63B29E905C24C823F19F25D27405B468FFC8092AD9C84BC8A4B1E4DC16D2B7`)
- 38-site `IDMan.exe` (`64BF39DD3BDD568389C84CF3546B4007B2B97775F728E485F670DFCBBF720DA0`)
- 39-site `IDMan.exe` (`599B15C25C1B9F06DCC4049B88E332AA105BBC0C382423F86BEC0D15F2224085`), superseded by the inside build
- inside `IDMan.exe` (`199E459FCC1D4ECDFDF3649C8E708FEE5EEC07CA22BD5AA9C253077B11F3BC6D`)

Keep the backups outside the repository. The hashes identify each build; the file names are local choices.

### 14.9 Notes

- The English anti-tamper sentence starts at file `0x3C3FCC` (VA `0x7C55CC`), XOR `0x3D`. The earlier pair "file `0x3C3FC4`, VA `0x7C4BC4`" is wrong twice: the sentence starts eight bytes later in the file, and file `0x3C3FC4` maps to VA `0x7C55C4`, while VA `0x7C4BC4` maps to file `0x3C35C4`, which holds RTTI text `CDialUpProcessor@@`. Map VAs with the section table, not with the `.text` delta.
- The default branch of the dispatcher at `0x4A8840` pushes six dialog strings, in order `0x7C5728`, `0x7C5710`, `0x7C56E0`, `0x7C5690`, `0x7C5610`, `0x7C55CC`, and the renderer `0x4A8170` decodes them with XOR `0x3D`. `0x7C55CC` is "The main IDM executive file is damaged.", `0x7C5610` is the "To continue downloading" paragraph, `0x7C5690` is the "Or, wait a few seconds" paragraph.
- The status word is `0x7D21F4`, read at `0x4A85C0`. Any status outside `1..0x2A` and `0x416` falls to the default branch above, so the text is generic and does not by itself prove a specific integrity check.
- The `CRYPT32.dll_unloaded` record is the crash signature. The unload is reference-counted: `LdrUnloadDll` on the crypt32 base is called from the certificate path (the Frida stack at 11:22:37 shows KERNELBASE, ntdll and crypt32 frames). Removing one caller at `0x4484B2` does not stop it. Holding a reference at the entry point does.
- `IDMGrHlp.exe` is not part of the crypt32 path. Its two fake-serial dialogs are handled separately at file offsets `0x52A1` and `0x52C8` (section 12).
- An IDM update replaces `IDMan.exe`. Re-apply the 30 sites, site 37, site 38, the section 15 patches, then recompute the checksum.
### 14.10 Verification status at this writing

- Installed image: `C:\Program Files (x86)\Internet Download Manager\IDMan.exe`, size `6,517,616`, SHA256 `199E459FCC1D4ECDFDF3649C8E708FEE5EEC07CA22BD5AA9C253077B11F3BC6D`. `AddressOfEntryPoint` RVA is `0x2D764C` (VA `0x6D764C`), file `0x2D6A4C` holds the 35-byte resident stub, file `0x2D6A80` holds the 79-byte dialog stub, file `0x250B62` is `E9 19 5F 08 00`, file `0x73B60` is `31 C0 C3`, file `0x893A6` is `31 C0 90 90 90`, file `0xA7F86` is `31 C0 90 90 90 90`, file `0x478B1` is `90` x7, file `0x4FA30` is `55 8D AC`, PE CheckSum stored and computed `0x0063B6F7`, `ExePath` names the install path. Installed with elevation and read back.
- Crypt32 module presence: pid 44352, launched from the install path, module list at 5 s contains `Crypt32.dll` at base `0x76C50000`, before any download. The entry stub ran.
- Unload survival: Frida trace on pid 64632, `LdrUnloadDll` called on crypt32 base `0x76C50000` at 11:22:37 from KERNELBASE, with the stack `KERNELBASE+0x16CF8C | ntdll+0x3EB30 | Crypt32+0x510CC | Crypt32+0x50F77 | KERNEL32+0x15D49`. Every 20-second sample after that still reports crypt32 present. The reference from site 38 absorbed the unload.
- Dialog suppression: opened with `WM_COMMAND 32783` on the main window. No `Internet Download Manager Registration` window, no fake-serial warning, and no licensed-to message appeared. The dialog procedure stub at `0x6D7680` closes the title length 38 dialog, and the warning and licensed-to functions are bypassed.
- Download: a 1.56 MB HTTPS file completed through IDM. Only the standard `Download File Info` and `Download complete` windows appeared. The serial is the random `A7K2M-9Q4XZ-3V8NB-6T1WP`; the blacklisted `12345-67890-...` is not used.
- The 41-minute soak below was recorded on the 39-site build. The inside build uses the same site 37 and site 38 crypt32 patches, so the unload fix is unchanged; the inside build was verified by the download and dialog checks above.
- The pre-fix 37-site build produced Event 1000 at 10:45:54 on the installed path: `CRYPT32.dll_unloaded`, `0xc0000005`, `0x0005d220`, process start time 08:44:18. That is the post-install crash that site 37 did not stop.
- Tray soak: pid 44352, launched from the install path at 11:25:47, main window closed to the tray at 11:27, sampled every 30 seconds in a local soak log outside the repository. At 11:58:29 the process had been alive for 32m42s, the monitor had 1860 s of samples, every sample reported `alive=True crypt32=True`, and no Application Error 1000 record appeared for the pid. This crosses the old 20 to 25 minute window by more than seven minutes with crypt32 still mapped.
- Cross-check: the same installed build survived an explicit `LdrUnloadDll` on crypt32 at 11:22:37 (pid 64632) and kept crypt32 in every later sample. The soak is a regression check; the module-presence evidence is the direct proof.
- Soak completed: at 12:07:01 the monitor reached its 2400 s limit with the process alive and `crypt32=True` in every 30 second sample. Process uptime from 11:25:47 to 12:07:01 is 41m14s, with no Application Error 1000 record. This is the verified end state.

### 14.11 The certificate path unloads crypt32

The 37-site build removed the destructor free but still crashed. The event log on 2026-11-14 recorded the proof:

```text
10:45:54  IDMan.exe  CRYPT32.dll_unloaded  0xc0000005  0x0005d220
          application start time 08:44:18
          path C:\Program Files (x86)\Internet Download Manager\IDMan.exe
```

A Frida trace of a fresh process showed the exact order:

```text
11:11:09  LOADW C:\WINDOWS\system32\Crypt32.dll -> 0x76C50000
11:11:16  LDRUNLOAD 0x76C50000 CRYPT32.dll caller KERNELBASE.dll+0x16CF8C
11:13:16  LDRUNLOAD 0x76C50000 CRYPT32.dll caller KERNELBASE.dll+0x16CF8C
```

`LdrUnloadDll` is reference-counted. Each certificate operation calls it once. As long as one reference is held for the life of the process, the module stays mapped and the cached pointer at `[0x7D3EBC]` remains valid. That is the invariant the fix must establish.

### 14.12 Site 38: resident crypt32 reference at the entry point

Site 38 adds one `LoadLibraryW("Crypt32.dll")` call before the original entry point and never frees it. The existing UTF-16 name at VA `0x70F888` is reused; the `LoadLibraryW` IAT slot is `0x6D83EC`.

Layout:

| Item | Value |
|---|---|
| cave VA | `0x6D764C` |
| cave file offset | `0x2D6A4C` |
| original entry | `0x684DEC` |
| new entry | `0x2D764C` (RVA) |
| stub length | 35 bytes |

Stub bytes:

```text
E8 00 00 00 00        call $+5
58                    pop eax
2D 51 76 2D 00        sub eax, 0x2D7651
89 C3                 mov ebx, eax
60                    pushad
8D 83 88 F8 30 00     lea eax, [ebx+0x30F888]
50                    push eax
8B 93 EC 83 2D 00     mov edx, [ebx+0x2D83EC]
FF D2                 call edx
61                    popad
E9 7D D7 FA FF        jmp 0x684DEC
```

The `call $+5` / `pop eax` / `sub` sequence recovers the runtime image base, so the stub works with ASLR. `pushad` / `popad` preserve the register state across the call. The `jmp` is relative and also ASLR-safe. The stub fits in the zero padding at the end of `.text`.

Write the stub, set `AddressOfEntryPoint` to `0x2D764C`, then recompute the checksum. If the build has a different cave or entry, recompute the `sub` immediate, the two displacements and the `jmp` rel32 from the actual values.

## 15. Inside dialog suppression (current build)

The inside build keeps the original registration status function at `0x450630`. It suppresses the UI directly, so no Python, watcher, or external process is needed.

### 15.1 Sites 40 to 43

| Site | File offset | Original bytes | Patch bytes | VA | Purpose |
|---|---:|---|---|---:|---|
| 40 | `0x250B62` | `8B FF 55 8B EC` | `E9 19 5F 08 00` | `0x651762` | Dialog procedure jump to the cave stub |
| 41 | `0x73B60` | `6A FF 68 88 78 6A` | `31 C0 C3 88 78 6A` | `0x474760` | Warning function returns 0 |
| 42 | `0x893A6` | `E8 F5 24 06 00` | `31 C0 90 90 90` | `0x489FA6` | Skip the licensed-to confirmation |
| 43 | `0xA7F86` | `FF 15 68 86 6D 00` | `31 C0 90 90 90 90` | `0x4A8B86` | Skip the custom dialog wrapper |

Site 40 is a 5-byte jump to the cave at file `0x2D6A80` (VA `0x6D7680`). The cave replays the original prologue, checks `WM_INITDIALOG`, and if the dialog title length is 38 it posts `WM_CLOSE` and returns 1. The registration title `Internet Download Manager Registration` is 38 characters. Every other dialog jumps back to `0x651767`.

Cave bytes, 79 bytes at file `0x2D6A80`:

```text
8B FF
55
8B EC
81 7D 0C 10 01 00 00
0F 85 D5 A0 F7 FF
60
E8 00 00 00 00
5B
81 EB 98 76 2D 00
8B 75 08
56
8B 83 E4 87 2D 00
FF D0
83 F8 26
75 19
6A 00
6A 00
6A 10
56
8B 83 E8 87 2D 00
FF D0
61
B8 01 00 00 00
5D
C2 10 00
61
E9 98 A0 F7 FF
```

Disassembly:

```text
006D7680 8B FF              mov edi, edi
006D7682 55                 push ebp
006D7683 8B EC              mov ebp, esp
006D7685 81 7D 0C 10 01 00 00  cmp dword ptr [ebp+0xC], 0x110
006D768C 0F 85 D5 A0 F7 FF  jne 0x651767
006D7692 60                 pushad
006D7693 E8 00 00 00 00     call 0x6D7698
006D7698 5B                 pop ebx
006D7699 81 EB 98 76 2D 00  sub ebx, 0x2D7698
006D769F 8B 75 08           mov esi, dword ptr [ebp+8]
006D76A2 56                 push esi
006D76A3 8B 83 E4 87 2D 00  mov eax, dword ptr [ebx+0x2D87E4]
006D76A9 FF D0              call eax
006D76AB 83 F8 26           cmp eax, 0x26
006D76AE 75 19              jne 0x6D76C9
006D76B0 6A 00              push 0
006D76B2 6A 00              push 0
006D76B4 6A 10              push 0x10
006D76B6 56                 push esi
006D76B7 8B 83 E8 87 2D 00  mov eax, dword ptr [ebx+0x2D87E8]
006D76BD FF D0              call eax
006D76BF 61                 popad
006D76C0 B8 01 00 00 00     mov eax, 1
006D76C5 5D                 pop ebp
006D76C6 C2 10 00           ret 0x10
006D76C9 61                 popad
006D76CA E9 98 A0 F7 FF     jmp 0x651767
```

`0x2D87E4` is the IAT slot for `GetWindowTextLengthW`; `0x2D87E8` is the IAT slot for `PostMessageA`. The stub recovers the runtime image base in `EBX` and preserves all registers with `pushad`/`popad`.

### 15.2 Serial

Use a random synthetic serial in the 5-5-5-5 format, for example `A7K2M-9Q4XZ-3V8NB-6T1WP`. The known `12345-67890-12345-67890` is on the local blacklist and triggers the status 1/2 path and the licensed-to confirmation even with the UI patches. Do not use a leaked key.

### 15.3 Verification

- Opening `WM_COMMAND 32783` (Registration) produces no `Internet Download Manager Registration` window, no fake-serial warning, and no licensed-to message.
- A normal download shows only the standard `Download File Info` and `Download complete` windows.
- File `0x4FA30` remains the original `55 8D AC`, not the old status stub.

### 15.4 Superseded status stub

An earlier experiment replaced the status function at `0x4FA30` with `31 C0 C3`. It suppressed the warning but forced the display to Trial and did not stop the download-time licensed-to dialog. Do not apply it to the inside build.

## 16. Complete build from pristine

This is the authoritative build path. It reproduces the installed inside binary byte for byte from the pristine 6.43 build 18 file, using only the Python standard library. Sections 4, 11, 13, 14 and 15 explain each site; the script below is the execution path, and the final hash is the acceptance test.

Requirements:

- Windows 10 or 11, 64-bit.
- Python 3.8 or newer on `PATH`.
- The pristine `IDMan.exe`, size `6,517,616`, SHA256 `A705C0154FAFC7CD509DECF165CB6F6C050B6521B40ADB6F730DD827C86051C7`.
- Administrator rights for the copy into `C:\Program Files (x86)\Internet Download Manager`.

Use the pristine file from the IDM 6.43 build 18 installer, or a backup kept outside the repository. Verify the hash before running the script. The script refuses an already patched file.

Save the pristine file as `IDMan.pristine.exe`, save the script as `build_final.py`, and run:

```text
python build_final.py IDMan.pristine.exe IDMan.patched.exe
```

Expected output:

```text
checksum 0x0063B6F7
sha256  199E459FCC1D4ECDFDF3649C8E708FEE5EEC07CA22BD5AA9C253077B11F3BC6D
PASS
```

The script refuses a different size or hash. Do not patch an already patched file. Do not edit the patch list by hand; it is the exact byte diff between the pristine and installed images. Some entries are one or two bytes inside a larger instruction. That is intentional: the list is the minimal byte diff, not the instruction boundaries. The final SHA256 is the acceptance test.

```python
#!/usr/bin/env python3
"""Build the inside IDMan.exe 6.43 build 18 image from the pristine file.

The script checks the pristine SHA256, applies the exact byte patches,
recomputes the PE checksum with no third party modules, and verifies the
final SHA256. It refuses any other input.
"""

import hashlib
import struct
import sys

PRISTINE_SHA256 = "A705C0154FAFC7CD509DECF165CB6F6C050B6521B40ADB6F730DD827C86051C7"
FINAL_SHA256 = "199E459FCC1D4ECDFDF3649C8E708FEE5EEC07CA22BD5AA9C253077B11F3BC6D"
PRISTINE_SIZE = 6517616

PATCHES = [
    (0x120, bytes.fromhex("4C 76 2D 00")),
    (0x101D4, bytes.fromhex("E8 06 05 FF FF 90 C3")),
    (0x478B1, bytes.fromhex("90 90 90 90 90 90 90")),
    (0x4D006, bytes.fromhex("E8 D4 36 FB FF 90")),
    (0x4FFC4, bytes.fromhex("EB")),
    (0x50C1D, bytes.fromhex("00")),
    (0x55DD0, bytes.fromhex("33 C0 C3")),
    (0x5A4B0, bytes.fromhex("B0 01 C3")),
    (0x5A830, bytes.fromhex("B0 01 C3")),
    (0x6640B, bytes.fromhex("E8 CF A2 F9 FF 90")),
    (0x6C073, bytes.fromhex("68 FF FF FF 7F 90 90")),
    (0x6C08C, bytes.fromhex("90 90")),
    (0x6C09A, bytes.fromhex("83 C4 0C 90 90")),
    (0x6C0CF, bytes.fromhex("E8 0B 46 F9 FF 90")),
    (0x73B60, bytes.fromhex("31 C0 C3")),
    (0x74E84, bytes.fromhex("31 C0 90 90 90")),
    (0x76666, bytes.fromhex("FF FF FF 7F")),
    (0x7C1A0, bytes.fromhex("C3")),
    (0x7EA43, bytes.fromhex("31 C0 90 90 90")),
    (0x863E9, bytes.fromhex("E9 79 01 00")),
    (0x863EE, bytes.fromhex("90")),
    (0x88C15, bytes.fromhex("E9 DA 0A 00 00")),
    (0x893A6, bytes.fromhex("31 C0 90 90 90")),
    (0x896F4, bytes.fromhex("8B 75 08 83 FE 10 74 0A 8B C6 83 E8 01 E9 17 F5 FF FF 6A 00 FF 77 20 FF 15 DC 87 6D 00 E9 34 F5 FF FF")),
    (0x8DA5D, bytes.fromhex("FF FF FF 7F")),
    (0x8DA77, bytes.fromhex("FF FF FF 7F")),
    (0x914DD, bytes.fromhex("E8 A5 13 03 00 90")),
    (0x93B5F, bytes.fromhex("31 C0 90 90 90")),
    (0xA7F86, bytes.fromhex("31 C0 90 90 90 90")),
    (0xB7E27, bytes.fromhex("58 90 90 90 90 90")),
    (0xE21BE, bytes.fromhex("58 90 90 90 90 90")),
    (0xE2647, bytes.fromhex("58 90 90 90 90 90")),
    (0x120D5C, bytes.fromhex("E8 7E F9 ED FF 90")),
    (0x14E902, bytes.fromhex("58 90 90 90 90 90")),
    (0x250B62, bytes.fromhex("E9 19 5F 08 00")),
    (0x25F5A0, bytes.fromhex("C3 90 90 90 90 90")),
    (0x2D6A4C, bytes.fromhex("E8 00 00 00 00 58 2D 51 76 2D 00 89 C3 60 8D 83 88 F8 30 00 50 8B 93 EC 83 2D 00 FF D2 61 E9 7D D7 FA FF")),
    (0x2D6A80, bytes.fromhex("8B FF 55 8B EC 81 7D 0C 10 01 00 00 0F 85 D5 A0 F7 FF 60 E8 00 00 00 00 5B 81 EB 98 76 2D 00 8B 75 08 56 8B 83 E4 87 2D 00 FF D0 83 F8 26 75 19 6A 00 6A 00 6A 10 56 8B 83 E8 87 2D 00 FF D0 61 B8 01 00 00 00 5D C2 10 00 61 E9 98 A0 F7 FF")),
]


def pe_checksum(data):
    """Standard PE checksum, checksum field treated as zero."""
    total = 0
    for i in range(0, len(data), 2):
        if 0x150 <= i < 0x154:
            continue
        word = data[i] | (data[i + 1] << 8)
        total += word
        total = (total & 0xFFFF) + (total >> 16)
    total = (total & 0xFFFF) + (total >> 16)
    return (total + len(data)) & 0xFFFFFFFF


def build(pristine):
    data = bytearray(pristine)
    for offset, patch in PATCHES:
        data[offset:offset + len(patch)] = patch
    checksum = pe_checksum(bytes(data))
    data[0x150:0x154] = struct.pack("<I", checksum)
    return bytes(data), checksum


def main():
    if len(sys.argv) != 3:
        print("usage: build_final.py <pristine IDMan.exe> <output IDMan.exe>")
        return 2
    src, dst = sys.argv[1], sys.argv[2]
    pristine = open(src, "rb").read()
    if len(pristine) != PRISTINE_SIZE:
        print("FAIL size %d, expected %d" % (len(pristine), PRISTINE_SIZE))
        return 1
    digest = hashlib.sha256(pristine).hexdigest().upper()
    if digest != PRISTINE_SHA256:
        print("FAIL pristine SHA256 %s" % digest)
        return 1
    data, checksum = build(pristine)
    open(dst, "wb").write(data)
    final = hashlib.sha256(data).hexdigest().upper()
    print("checksum 0x%08X" % checksum)
    print("sha256  %s" % final)
    if final != FINAL_SHA256:
        print("FAIL final SHA256, expected %s" % FINAL_SHA256)
        return 1
    print("PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
```

### 16.1 Install

1. Close `IDMan.exe` and `IDMGrHlp.exe`.
2. Back up the installed `IDMan.exe` and `IDMGrHlp.exe` outside Program Files.
3. Open an elevated PowerShell and copy the patched file:

```powershell
Copy-Item .\IDMan.patched.exe 'C:\Program Files (x86)\Internet Download Manager\IDMan.exe' -Force
Copy-Item .\IDMGrHlp.patched.exe 'C:\Program Files (x86)\Internet Download Manager\IDMGrHlp.exe' -Force
```

4. Patch the helper with the script in section 12.2. The patched helper SHA256 must be `F5E7360A0C376247507218AC92392BD8B71AF70376E3BF1058C77AFED575B36D`.
5. Create the registry values in section 5.
6. Set `HKCU\Software\DownloadManager\ExePath` to `C:\Program Files (x86)\Internet Download Manager\IDMan.exe`.
7. Start IDM and run the checks in section 14.7.

### 16.2 Failure modes

| Symptom | Cause | Fix |
|---|---|---|
| Process exits in about 0.12 s with no window | `ExePath` does not match the launched image | Set `ExePath` to the exact path that was launched |
| `Crypt32.dll` absent at startup | The entry stub is missing or `AddressOfEntryPoint` was not set to `0x2D764C` | Rebuild with section 16; verify file `0x120` = `4C 76 2D 00` |
| Registration window, fake-serial warning, or licensed-to dialog appears | The section 15 dialog patches are missing | Apply sites 40 to 43 and the 79-byte cave at `0x2D6A80`; do not use the old status stub at `0x4FA30` |
| Display shows Trial with the full build | The old status stub at `0x4FA30` is applied, or the serial is blacklisted | Restore `55 8D AC` at `0x4FA30` and use a random 5-5-5-5 serial |
| Final SHA256 differs | Wrong pristine build, a missing site, or a hand-edited patch list | Re-run the script on the pristine file; do not patch an already patched file |
| `CRYPT32.dll_unloaded` still appears | The running image is not the inside build | Close IDM, reinstall the `199E459F...` hash, verify file `0x2D6A4C` holds the stub |
| A soak ends when a second IDMan is launched | The single-instance mutex and the ExePath gate | Kill every IDMan before a soak; do not launch a second instance while testing |
| Installed file is write protected | Program Files ACL | Use an elevated PowerShell, not a normal prompt |
