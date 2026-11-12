# Internet Download Manager Playbook

Target: Internet Download Manager 6.43 build 18

File: `IDMan.exe`

Architecture: 32-bit x86, PE32, native C++

Status: locally verified

This playbook describes a local patch set. It does not ship a patched binary or a compiled patcher.

## 1. Target profile

| Item | Value |
|---|---|
| Vendor | Tonec Inc. |
| Product | Internet Download Manager |
| Version | 6.43 build 18 |
| Install directory | `%ProgramFiles(x86)%\Internet Download Manager` |
| Main executable | `IDMan.exe` |
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

The fully patched build in this playbook has:

```text
size            6,517,616 bytes
SHA256          BACF3DCC44073935FD72493A2578F0A7295FE2F447A9DCF68EC0C4CD3774A020
```

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

| Status | Meaning | Handler |
|---:|---|---|
| 0 | registered or continue | `0x00452CB6` |
| 1 | counterfeit serial | `0x00452CCD` |
| 2 | blocked serial details | `0x00452DD0` |
| 3 | counterfeit or blocked, exit | `0x00452E73` |
| 4, 6 | trial with days left | `0x00452EAB` |
| 5, 7, 9, 10, 12 | exit | `0x00452EFD` |
| 8 | license expired | `0x00452E8F` |
| 11 | serial used on another computer | `0x00452CEC` |

The counterfeit return is at `0x0045181C`:

```text
B8 03 00 00 00   mov eax, 3
E9 ...           jmp 0x00450C88
```

Changing the immediate to 0 makes the switch take the status 0 path. Do not patch the `.data` flag at `0x007C4D24` to 0 in this build. That flag is the unregistered marker, and forcing it to 0 causes the registration dialog to open on startup even when the serial is present. Keep it at 1 and use the validator stubs and the status patch instead.

## 4. Patch sites

All offsets below are file offsets in `IDMan.exe`. Convert a virtual address to a file offset with:

```text
file offset = virtual address - 0x00401000 + 0x00000400
```

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
Set-ItemProperty -Path $key -Name Serial -Value '12345-67890-12345-67890'
Set-ItemProperty -Path $key -Name FName  -Value 'Test'
Set-ItemProperty -Path $key -Name LName  -Value 'User'
Set-ItemProperty -Path $key -Name Email  -Value 'test@example.com'
```

Use a synthetic serial. Do not use a leaked key.

IDM may also read the values from `HKLM\SOFTWARE\WOW6432Node\Internet Download Manager`. The `HKCU` path is sufficient when the machine-wide key has no registration values.

## 6. Finding the sites in a new build

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
- Wait at least 90 seconds. IDM must remain running and no `buy2.html` or `buy_idm2.html` browser process may appear.
- Let a small download complete and compare its size with the server.

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

The SHA256 of the patched file must be:

```text
BACF3DCC44073935FD72493A2578F0A7295FE2F447A9DCF68EC0C4CD3774A020
```

Any other hash means the patch set, order, or target build is wrong.

## 8. Rollback

1. Close `IDMan.exe`.
2. Restore the pristine `IDMan.exe` from the backup outside the install directory.
3. Delete `Serial`, `FName`, `LName`, and `Email` under `HKCU\Software\DownloadManager`.
4. Start IDM and confirm the trial state returns.

The pristine backup must be kept outside `%ProgramFiles(x86)%\Internet Download Manager` so an update or a media build cannot embed it.

## 9. Packaging and distribution

Do not commit the patched `IDMan.exe`, a keygen, or a compiled patcher to a public or private repository. Distributing a ready-to-run circumvention binary can trigger a DMCA notice and repository removal, and private repositories are not immune to a valid notice.

Commit only this playbook, the project README, and local build notes. If a patcher is needed, build it locally and keep the binary outside the repository.

## 10. Notes

- The serial format check is not a license check. Any syntactically valid synthetic serial passes the local format stage.
- The online branch and the counterfeit status are separate. Patching only one of them leaves either the exit dialog or the warning path active.
- The two warning call sites are independent. Patching only one leaves the other message visible.
- The first buy-page builder at `0x0047CDA0` and the timer buy-page opener at `0x0047F643` are separate. Patching only the builder leaves the startup buy page and the timer exit active.
- The timer exit is controlled by the unregistered check at `0x00486FE9`. The buy-page opener alone does not stop the application close.
- `LastCheckQU` is a timestamp, not a boolean. Do not set it to a far-future value as the only update fix; patch the check function instead.
- IDM replaces `IDMan.exe` on update. Re-run the discovery workflow after every update.
- The registry values are per-user. A new Windows profile needs the four values again.

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
