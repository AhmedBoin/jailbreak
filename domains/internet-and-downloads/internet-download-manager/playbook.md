# Internet Download Manager: agent crack runbook

Target: Internet Download Manager 6.x, 32-bit native builds. The worked example is 6.43 build 18. Every address in the worked example is a reference for that exact build, not a contract for the next one.

This document is written to be executed, not read. It assumes an agent with shell access, Python, and optionally Frida. Each phase ends with a gate. Do not start the next phase until the current gate passes. A build is done when the verification matrix in phase 9 passes, not when the binary stops showing the registration window.

The one rule that matters: **patch the decision the running binary makes, not the bytes a static diff shows.** A byte-perfect manifest can still fail on a machine whose license state returns a different code. Confirm every license patch against a live hook before you trust it.

---

## 0. Contract

### 0.1 Deliverables

For a 6.x build, a finished crack has four artifacts:

| Artifact | Purpose |
|---|---|
| Patched `IDMan.exe` | The application with every layer below applied |
| Patched `IDMGrHlp.exe` | The helper, with the fake-serial dialogs suppressed |
| Manifest JSON | Every byte changed, with original and patch values |
| Gate log | The output of `tooling/gate.ps1`, stored with the manifest |

Never ship only the binary. The manifest is what makes the work reproducible and is the only defense against the next build silently breaking a patch.

### 0.2 Layer model

IDM has eight decision layers. Treat each as a separate problem with its own gate.

| Layer | What it decides | Failure symptom if wrong |
|---|---|---|
| Registry identity | Serial, name, email, display version, launched path | Silent exit in under a second, or a permanent trial state |
| Validators | Whether the serial and name are syntactically acceptable | Registration or fake-serial dialog |
| Status machine | Registered, trial, counterfeit, expired, blocked | Registration dialog, 15-day warning, exit with code 2 |
| UI | Registration, warning, licensed-to, buy page, update | Any of those windows |
| Lifecycle | Timers, tray close, `PostQuitMessage`, `ExitProcess` | Process disappears while idle or when the window is closed |
| Module lifetime | `crypt32.dll` load, use, unload | Crash with `CRYPT32.dll_unloaded` after HTTPS work |
| Helper | Periodic fake-serial dialogs from `IDMGrHlp.exe` | A second window appears minutes after launch |
| Integrity | PE checksum and self-checks | Exit, crash, or a repair prompt |

### 0.3 Ordering rules

1. Fix the status machine before touching the registration dialog. If the status still says unregistered, dismissing the dialog is read as a refusal and the process exits. Suppressing the dialog first only converts a visible problem into a silent one.
2. Fix the lifecycle before any soak test. A 20 minute soak that ends in a self-exit tells you nothing about crypt32.
3. Remove the crypt32 free before testing HTTPS. A crash after an HTTPS download is a lifetime bug, not a license bug.
4. Recompute the checksum last, after every code patch, including caves.
5. Test on a copy with `ExePath` pointed at the copy. Only write to `Program Files` after the gate passes.
6. Kill every IDMan process before any launch test. IDM is single instance, and a second copy exits in a fraction of a second, which looks exactly like a broken patch.

### 0.4 Workspace layout

```text
<work>/
  pristine/IDMan.exe          original, never modified
  pristine/IDMGrHlp.exe       original helper
  build/IDMan.exe             manifest output
  build/IDMGrHlp.exe
  manifest/6.43b18.json       patch list
  logs/                       gate output, hook output, WER queries
  export/                     registry export before changes
```

---

## 1. Phase 1: identify and baseline

### 1.1 Identify the build

Use two independent sources. Do not trust the installer name.

| Source | Command or location |
|---|---|
| File version resource | `(Get-Item IDMan.exe).VersionInfo.FileVersion` or `pefile` |
| Registry | `HKCU\Software\DownloadManager\idmvers`, for example `v6.43b18 Full` |
| About dialog | Menu, About |
| File size and hash | `Get-FileHash IDMan.exe -Algorithm SHA256` |

Record the exact string. Two builds with the same marketing version can have different offsets.

### 1.2 Back up and hash

```powershell
$src = 'C:\Program Files (x86)\Internet Download Manager'
$work = 'C:\idm-work'
New-Item -ItemType Directory -Force "$work\pristine" | Out-Null
Copy-Item "$src\IDMan.exe"    "$work\pristine\IDMan.exe"    -Force
Copy-Item "$src\IDMGrHlp.exe" "$work\pristine\IDMGrHlp.exe" -Force
reg export 'HKCU\Software\DownloadManager' "$work\export\downloadmanager.reg" /y
Get-FileHash "$work\pristine\IDMan.exe"    -Algorithm SHA256
Get-FileHash "$work\pristine\IDMGrHlp.exe" -Algorithm SHA256
```

Never patch the only copy. The pristine file is the input to the manifest and the reference for every original byte.

### 1.3 Record baseline behavior

Launch the original once and record:

1. The About dialog string and whether it says Trial or Full.
2. Whether a registration window appears at startup.
3. Every dialog title and its text.
4. How long the process lives with no input.
5. The exit code if it exits on its own.

This baseline is how you tell a crack failure from stock behavior. Stock 6.43 on an expired trial, for example, shows `Internet Download Manager has not been registered for 15 days. IDM is exiting...` and quits. That is not caused by your patch.

### 1.4 The ExePath gate

IDM compares the launched image path with `HKCU\Software\DownloadManager\ExePath`. A mismatch causes a silent exit in roughly 0.1 to 0.3 seconds with no window. This looks like a broken patch and is usually just a path mismatch.

Before every launch test:

```powershell
Set-ItemProperty 'HKCU:\Software\DownloadManager' -Name ExePath -Value '<exact path of the exe you are launching>'
```

The comparison is textual. `C:\Program Files (x86)\...` and `C:\PROGRA~2\...` are different strings. Use the same spelling you launch.

### 1.5 Single instance

IDM owns a named mutex and a window class. A second copy detects the first and exits almost immediately, usually with code 0. Dynamic tests must start from zero instances:

```powershell
Get-Process IDMan -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 1
```

If a probe exits in under a second, check for a running instance before you debug the binary. This exact confusion has produced more false "the crack is broken" reports than any patch bug.

### 1.6 Tooling

| Tool | Use |
|---|---|
| IDA Pro or Ghidra | Static analysis, xrefs, decompiler, jump tables |
| x64dbg (32-bit) | Breakpoints, memory patches, module list |
| `pefile`, `capstone` (Python) | Headers, sections, disassembly, patching |
| Frida | Runtime hooks, status code, dialogs, module lifetime |
| Process Monitor | Registry, file, and network behavior |
| API Monitor | `RegQueryValue`, `MessageBox`, `SetTimer`, `LoadLibrary` |
| Windows Event Viewer | WER `Application Error` records, faulting module and offset |

`tooling/hook-status.py` in this repository is the Frida probe described in phase 2. `tooling/patch.py` applies a manifest and fixes the checksum. `tooling/gate.ps1` runs the static and dynamic acceptance checks.

### Gate 1

- Version string recorded from two sources.
- Pristine copies hashed and stored outside the install directory.
- Registry exported.
- Baseline behavior recorded, including whether the stock app already exits on its own.
- One IDMan instance at most before any test.

---

## 2. Phase 2: runtime recon

### 2.1 Why runtime first

IDM encrypts its license messages at runtime (the caption arrives as `IDM_emc_<base64>`), so searching the binary for `fake serial` or `not been registered` finds nothing. The strings are decrypted in a wrapper just before `MessageBoxW`. A static string search therefore sends you to the wrong function or nowhere.

Worse, the status machine returns a small code whose value depends on the machine's registry state and elapsed days, not only on the build. The same binary can return 3 on one machine and 6 on another. Patching a `mov eax, 3` because a write-up said so is how a build passes a byte check and still opens the registration window.

The reliable method is to hook the status dispatcher, read the code the running binary returns, and patch that code. Everything else in the license layer is confirmation.

### 2.2 The status probe

Start with the dispatcher. In 6.43 it is at file offset `0x4FA30`, RVA `0x50630`, called once at startup. If you do not know it yet, find it in phase 3.4, then come back.

```text
python tooling/hook-status.py "<work>\build\IDMan.exe" --seconds 8 --dispatcher 0x50630 --wrapper 0x6D5C0
```

The tool spawns the process suspended, installs hooks, resumes it, and prints:

```text
[STATUS] t=0.14s code=0
[result] alive_after_probe=True
```

Read the code with the table in 3.4. A non-zero code is the patch target. Do not proceed to phase 3 until you have this number for the build and machine you are cracking.

The probe also logs `MessageBoxW` text and the caller's module offset, `DialogBoxParamW` calls with the procedure pointer, and `ExitProcess`, `TerminateProcess`, `RtlExitUserProcess`, `PostQuitMessage` calls with backtraces. That is enough to separate a dialog problem from an exit problem.

### 2.3 Reading the probe output

| Output | Meaning | Next move |
|---|---|---|
| `code=0` | Registered | Skip to phase 4, UI only if needed |
| `code=3` | Counterfeit | Patch the counterfeit return, phase 3.5 |
| `code=6` | Trial expired | Patch the trial-expired return, phase 3.5 |
| `code=7` | Empty or unreadable serial | Fix the registry identity first, then re-probe |
| `code=10` | Serial used elsewhere | Patch that return, or change the serial |
| `code=12` | Blocked serial | Patch that return, or change the serial |
| `MessageBox` with `IDM_emc_` caption | Encrypted nag reached | The status code is the cause; do not chase the message |
| `ExitProcess` within 0.5s | Status path exits directly | Patch the status return, not the exit |
| No status call at all | Wrong RVA, or the process never reached the check | Verify the binary, kill other instances, re-probe |

### 2.4 The lifecycle probe

Run the same tool with `--seconds 20` and no interaction. Any `PostQuitMessage` or `ExitProcess` in the first twenty seconds is a lifecycle bug, not a license dialog. Note the timestamp and backtrace.

### 2.5 The module probe

For the crypt32 layer, hook `LoadLibraryW`, `FreeLibrary`, and `LdrUnloadDll` and log the module name, return value, thread id, and stack. Add the hook to a local copy of `hook-status.js` when you reach phase 6. The point is to see whether something frees crypt32 while a worker still holds a function pointer.

### Gate 2

- Status code read from the running binary and recorded with the build hash.
- Dialog titles recorded, if any.
- First twenty seconds contain no unexplained `PostQuitMessage` or `ExitProcess`.
- You can state, in one sentence, which layer is producing the visible symptom.

---

## 3. Phase 3: license layer

### 3.1 Registry identity

The license and identity values live under `HKCU\Software\DownloadManager`.

| Value | Type | Role |
|---|---|---|
| `Serial` | REG_SZ | 23 characters, hyphens at positions 5, 11, 17 |
| `FName`, `LName` | REG_SZ | Name used by the licensed-to text |
| `Email` | REG_SZ | Email |
| `idmvers` | REG_SZ | Display version, for example `v6.43b18 Full` |
| `ExePath` | REG_SZ | Exact image path IDM expects to run from |
| `LastCheckQU` | REG_DWORD | Update check timestamp |

Set a synthetic serial that matches the format. The famous `12345-67890-12345-67890` is blacklisted and triggers the licensed-to path even with the UI patched.

```powershell
$key = 'HKCU:\Software\DownloadManager'
Set-ItemProperty $key -Name Serial -Value 'A7K2M-9Q4XZ-3V8NB-6T1WP'
Set-ItemProperty $key -Name FName  -Value 'Test'
Set-ItemProperty $key -Name LName  -Value 'User'
Set-ItemProperty $key -Name Email  -Value 'test@example.com'
Set-ItemProperty $key -Name ExePath -Value 'C:\Program Files (x86)\Internet Download Manager\IDMan.exe'
```

Do not set `idmvers` by hand if the status patch works. The app writes it. Forcing `Full` on top of an expired state is one way to reach the fake-serial branch with a mismatched display string.

### 3.2 Find the validators

Start from the registry value name. The UTF-16 string `Serial` is at file `0x30589C`, VA `0x706C9C`. Its `push` references are the license readers:

```text
0x122C36 and 0x122FB0 in a 6.43 build, RVAs 0x123836 and 0x123BB0
```

A validator or status reader typically:

1. Opens `HKCU\Software\DownloadManager`.
2. Queries `Serial`, `FName`, `LName`, `Email`.
3. Checks length 23 and hyphens at 5, 11, 17.
4. Returns a boolean in `AL` or a status code in `EAX`.

Constants worth anchoring on:

| Constant | Meaning |
|---|---|
| `0x17` (23) | Serial length |
| `0x2D` (`-`) | Hyphen |
| `5`, `0xB`, `0x11` | Hyphen positions |
| `0x100`, `0x104` | Registry buffer size |

If the strings are built dynamically, break on `RegQueryValueExW` and log the value name and output buffer. The license values appear at startup.

### 3.3 Patch the validators

Boolean in `AL`:

```text
B0 01 C3        mov al, 1 ; ret
```

Integer in `EAX`:

```text
31 C0 FF C0 C3  xor eax, eax ; inc eax ; ret
```

Stack discipline decides whether a bare `ret` is legal. If the caller cleans arguments with `add esp, n`, the function is cdecl and `ret` is correct. If the caller does not clean, the function is stdcall and you need `ret n` where `n` is the argument byte count. A wrong cleanup crashes on the next `ret`, not at the patch site.

The 6.43 sites are `0x5A4B0` and `0x5A830`, both `55 8B EC` to `B0 01 C3`.

### 3.4 Find the status dispatcher

The dispatcher is the function that combines the validator results and returns the license code. In 6.43 it is a large function starting at file `0x4FA30` (RVA `0x50630`) with a single caller at RVA `0x5250A`.

The code values observed in 6.43:

| Code | Meaning | Evidence |
|---:|---|---|
| 0 | Registered | Normal return on a working build |
| 1 | Counterfeit warning path | Return immediate |
| 2 | Blocked serial details | Return immediate |
| 3 | Counterfeit | `B8 03 00 00 00` at file `0x50C1C` |
| 6 | Trial expired | `B8 06 00 00 00` at file `0x50083`, observed on an expired machine |
| 7 | Empty or unreadable serial | `B8 07 00 00 00` at file `0x50CFB` |
| 10 | Serial used on another computer | `B8 0A 00 00 00` at file `0x50D5C` |
| 12 | Blocked serial | `B8 0C 00 00 00` at file `0x50DBD` |

Codes 6, 7, and 12 were read from the running binary, not from a write-up. Confirm the code on your machine with the phase 2 probe before patching. The day counter that produces 6 is registry state, so a byte-identical binary can return 3 on one machine and 6 on another.

The caller switches on the code, often through a jump table:

```text
call status_function
cmp eax, 0xA
ja default
jmp dword ptr [eax*4 + table]
```

Each case either shows a dialog, opens a buy page, or exits. Map the table before patching so you know which case you are removing.

### 3.5 Patch the status return

Patch the immediate that feeds the shared epilogue, not the caller and not the whole function. For every code the machine can return:

```text
B8 03 00 00 00  ->  B8 00 00 00 00      counterfeit becomes registered
B8 06 00 00 00  ->  31 C0 90 90 90      trial expired becomes registered
```

The five-byte `xor eax, eax` plus nops is used when the immediate is followed by a jump to the epilogue; it keeps the instruction length and does not disturb the flags the epilogue reads. `B8 00 00 00 00` is equivalent when only the value matters. Either is fine as long as the byte count matches.

Rules:

- Patch only codes that the running binary actually returns. A manifest full of speculative patches is harder to audit than one with three verified sites.
- Do not replace the whole dispatcher with `31 C0 C3`. Some builds use the same function to produce the About display string, so forcing 0 can show `Trial` while suppressing the warning. Patch the return values instead.
- Re-probe after the patch. The gate expects code 0.

### 3.6 Why not just close the registration dialog

It is tempting to leave the status at 6 and close the registration window with a cave. That produces a worse failure. The startup path treats a dismissed registration dialog as a refusal: it suppresses the warning (which you patched), then calls the exit path. The visible dialog becomes a silent exit with code 2 in about 0.2 seconds, and the browser integration reports `0x80010108` because IDM is no longer running.

The dialog cave in phase 4.1 is a suppression layer for builds that show the dialog for a reason you have not found yet. It is not a license fix.

### Gate 3

- Status probe returns 0 on the patched build.
- About dialog shows the registered state, not Trial.
- No registration window at startup.
- No fake-serial or 15-day warning.
- Process is still alive after 30 seconds with no interaction.

---

## 4. Phase 4: UI suppression

Only start this phase after gate 3. With the status at 0 these patches are insurance, not the primary fix. They still matter because a future build may reach the UI through a path your status patch does not cover.

### 4.1 Registration dialog

Find the dialog procedure:

1. List resources with PE-bear, Resource Hacker, or `pefile`.
2. Find the dialog whose title is `Internet Download Manager Registration` or whose controls include `Serial`, `First Name`, `Last Name`, `Email`.
3. Find the `DialogBoxParamW` or `CreateDialogParamW` call that uses the template.
4. The `lpDialogFunc` argument is the procedure. In x86 stdcall the arguments are pushed right to left, so the procedure pointer appears as `push offset proc` near the call.
5. The prologue is usually `8B FF 55 8B EC`.

Procedure arguments:

```text
[ebp+8]   HWND
[ebp+0xC] UINT message
[ebp+0x10] WPARAM
[ebp+0x14] LPARAM
```

`WM_INITDIALOG` is `0x110`.

A cave that closes only the registration dialog:

```text
8B FF                    mov edi, edi
55                       push ebp
8B EC                    mov ebp, esp
81 7D 0C 10 01 00 00     cmp dword ptr [ebp+0xC], 0x110
0F 85 <rel32>            jne original_after_prologue
60                       pushad
E8 00 00 00 00           call $+5
5B                       pop ebx
81 EB <pop_rva>          sub ebx, pop_rva
8B 75 08                 mov esi, dword ptr [ebp+8]
56                       push esi
8B 83 <iat_len>          mov eax, dword ptr [ebx+iat_len]
FF D0                    call eax
83 F8 26                 cmp eax, 0x26
75 19                    jne forward
6A 00                    push 0
6A 00                    push 0
6A 10                    push 0x10
56                       push esi
8B 83 <iat_post>         mov eax, dword ptr [ebx+iat_post]
FF D0                    call eax
61                       popad
B8 01 00 00 00           mov eax, 1
5D                       pop ebp
C2 10 00                 ret 0x10
forward:
61                       popad
E9 <rel32>               jmp original_after_prologue
```

`0x26` is 38, the length of `Internet Download Manager Registration`. `pop_rva` is the RVA of the instruction after `call $+5`, where `pop ebx` lands. `pushad` and `popad` preserve the registers the original procedure expects. `PostMessageA(hwnd, WM_CLOSE, 0, 0)` closes the dialog and returning 1 says the message was handled.

In 6.43 the procedure is at file `0x250B62` (RVA `0x251762`), the cave at file `0x2D6A80`, and the IAT slots are `GetWindowTextLengthW` at RVA `0x2D87E4` and `PostMessageA` at RVA `0x2D87E8`.

If the title changes, count the new title or replace the length check with `GetWindowTextW` and a string compare. If the dialog is created with `CreateDialogParamW` and shown later with `ShowWindow`, patch the creation or the show call instead.

Remember 3.6: this cave does not fix an unregistered status.

### 4.2 Warning sites

IDM's license messages are decrypted at runtime, so plain string search fails. Work from the message wrapper instead. In 6.43 the wrapper is at file `0x6C9C0` (RVA `0x6D5C0`); it builds the `IDM_emc_...` caption and calls `MessageBoxW` at RVA `0x6D7CA`. The wrapper has four callers:

```text
RVA 0x74899, 0x749EB, 0x74B78, 0x74CD8
```

Each caller is a small message helper that formats text and returns the MessageBox result. The dispatcher does not call them directly; the status case or the download path does.

Two ways to suppress:

1. Patch the shared warning function to return 0. In 6.43 that function starts at file `0x73B60`, patched to `31 C0 C3`.
2. Patch the call sites that push the warning text. The 6.43 manifest patches the two known sites at file `0x93B5F` and `0x74E84` with `31 C0 90 90 90`.

If arguments are pushed immediately before a patch site, removing the call leaves them on the stack. Add the matching `add esp, n`, or replace the call with a `ret n` gadget. In 6.43 the two sites have no pending arguments.

### 4.3 Licensed-to confirmation

The licensed-to text is formatted and then shown. Patch the call that shows it:

```text
E8 <rel32>      ->  31 C0 90 90 90
```

The 6.43 site is file `0x893A6`. If the call takes pushed arguments, clean them. If the dialog is a custom resource rather than a message box, use the title or control check from 4.1.

### 4.4 Buy page

- Search for `buy`, `buy2.html`, `buy_idm2.html`, and any URL builder.
- Xref the string to the URL builder or to `ShellExecuteW`.
- Patch the builder to return 0, or patch the `ShellExecuteW` call.
- Check the timer path too. In 6.43 there is a timer that opens the buy page after a delay: file `0x7EA43` patched to `31 C0 90 90 90`, and the timer `ShellExecuteA` call at file `0x914DD` replaced with a `ret 0x18` gadget.
- The builder itself is patched to `C3` at file `0x7C1A0`.

### 4.5 Update check

- Search for `LastCheckQU`.
- Find the function that reads or writes it.
- Patch the check function to return 0. In 6.43 that is file `0x55DD0`, `55 8B EC` to `33 C0 C3`.
- If `LastCheckQU` is absent in a new build, log WinInet or WinHttp calls during startup and patch the timer that performs the request.
- `Help -> Check for updates` may be a separate manual path. Patch the shared check, not just the timer.

### Gate 4

- Registration menu: no window, no warning, no licensed-to.
- About: registered state, no trial counter.
- Download: only `Download File Info` and `Download complete`.
- No browser process opened with `buy2.html` or `buy_idm2.html`.
- `LastCheckQU` does not change during a normal launch.

---

## 5. Phase 5: lifecycle

### 5.1 Enumerate timers

Find every `SetTimer` call:

```text
push 0                 ; lpTimerFunc = NULL
push <interval>
push <timer_id>
push <hwnd>
call SetTimer
```

| Interval | Milliseconds | Immediate |
|---:|---:|---|
| 10 seconds | 10,000 | `0x2710` |
| 12 seconds | 12,000 | `0x2EE0` |
| 32 seconds | 32,000 | `0x7D00` |
| 3 minutes | 180,000 | `0x2BF20` |
| 10 minutes | 600,000 | `0x927C0` |
| 20 minutes | 1,200,000 | `0x124F80` |

When the callback is `NULL`, the window procedure receives `WM_TIMER` (`0x113`). Inspect each timer id branch for `PostQuitMessage`, `ExitProcess`, or a dialog that leads to exit.

Do not assume the 20 minute timer is the self-exit. In 6.43 the 20 minute arms were exonerated; the real crash was the crypt32 unload. Inspect the case bodies.

In 6.43 the exit timers are neutralized by raising their intervals:

| File offset | Original | Patch | Effect |
|---|---|---|---|
| `0x8DA76` | `68 10 27 00 00` | `68 FF FF FF 7F` | 10 second timer becomes INFINITE |
| `0x6C073` | `8D 8E 20 4E 00 00 51` | `68 FF FF FF 7F 90 90` | 32 second timer becomes INFINITE |
| `0x6C08C` | `75 41` | `90 90` | Remove the timer exit branch |
| `0x6C09A` | `E8 B1 72 FB FF` | `83 C4 0C 90 90` | Skip the 12 second registration timer |
| `0x76666`, `0x8DA5C` | `68 20 BF 02 00` | `68 FF FF FF 7F` | 3 minute timer arms become INFINITE |

`0x7FFFFFFF` is the maximum `UINT`, which `SetTimer` treats as an interval far beyond any session.

### 5.2 PostQuitMessage

Find the `PostQuitMessage` IAT slot and every xref. A call site:

```text
6A 00                 push 0
FF 15 <IAT slot>      call dword ptr [PostQuitMessage]
```

Replace with:

```text
58                    pop eax
90 90 90 90 90        nop x5
```

`pop eax` removes the argument the preceding `push` placed, so the stack depth, return address, and SEH chain stay intact. This works only when the `push 0` is immediately before the call. For a tail jump:

```text
FF 25 <IAT slot>      jmp dword ptr [PostQuitMessage]
```

replace with:

```text
C3 90 90 90 90 90     ret ; nop x5
```

The 6.43 sites are `0x14E902`, `0xB7E27`, `0xE21BE`, `0xE2647`, and the thunk at `0x25F5A0`.

### 5.3 ExitProcess

Find the IAT slot and every xref. A direct call:

```text
FF 15 <IAT slot>      call dword ptr [ExitProcess]
```

Patch to a `ret` gadget:

```text
E8 <rel32> 90         call ret_gadget ; nop
```

The `call` pushes a return address and the gadget's `ret` returns to the next instruction. The original argument stays on the stack for the caller's cleanup. This preserves the stack and avoids returning from the middle of a function. Find a lone `C3` in a padding area of the same section for the rel32. In 6.43 a `ret 4` gadget at RVA `0x12DF` is used, which also discards the argument:

```text
E8 <rel32 to 0x12DF> 90
```

The five 6.43 sites are `0x101D4`, `0x4D006`, `0x6640B`, `0x6C0CF`, `0x120D5C`. The site at `0x101D4` also has an `int3` at `0x101DA`; patch it to `C3` so a stray call returns instead of breaking.

### 5.4 Tray close

Find the `WM_CLOSE` (`0x10`) case in the main window procedure and make it hide the window:

```text
ShowWindow(hwnd, SW_HIDE)
return 0
```

A cave is easier than inlining. The 6.43 site is file `0x88C15` (RVA `0x89815`) redirected with `E9 DA 0A 00 00` to a cave at file `0x896F4`:

```text
8B 75 08              mov esi, dword ptr [ebp+8]
83 FE 10              cmp esi, 0x10
74 0A                 je close
8B C6                 mov eax, esi
83 E8 01              sub eax, 1
E9 17 F5 FF FF        jmp 0x8981D
close:
6A 00                 push 0                 ; SW_HIDE
FF 77 20              push dword ptr [edi+0x20]
FF 15 DC 87 6D 00     call dword ptr [ShowWindow]
E9 34 F5 FF FF        jmp 0x8984A
```

The first jump returns to the original `je` after replaying the stolen prologue. The second jump enters the original dispatch table after the `WM_CLOSE` case. Check the jump targets against the pristine disassembly before trusting them; a one-byte misalignment crashes on the first close.

### 5.5 Exit codes

| Code | Meaning | How to confirm |
|---:|---|---|
| 0 | Clean shutdown, or a second instance handing off to the first | Check for a running IDMan before launching |
| 1 | Generic failure | Check the WER record |
| 2 | Dialog-cancel exit path, or an early abort | Reproduce under the phase 2 probe; look for `EndDialog` then exit |
| `0xC0000005` | Access violation | Check WER for the faulting module |
| `0xC0000409` | Stack cookie or fast-fail | A patch broke a function epilogue or a stack cleanup |

A process that exits with code 2 within half a second of launch, with no window, is either a second instance or the registration dialog being dismissed. Distinguish them before patching anything else.

### Gate 5

- Close the window: it disappears, the tray icon remains, the process stays alive.
- Ten minutes later the process is still alive in the tray.
- No WER `Application Error` for the pid.
- `crypt32.dll` still loaded after an HTTPS download (phase 6).

---

## 6. Phase 6: crypt32 lifetime

### 6.1 Symptom

The process disappears without a dialog. Windows Error Reporting records:

```text
Faulting module name: CRYPT32.dll_unloaded
Exception code: 0xc0000005
Fault offset: 0x0005d220 (varies with the crypt32 build)
```

The instruction pointer is inside a module that has been unmapped. The offset is not an export. Uptime at death varies from about 30 seconds to 45 minutes; the 20 to 25 minute cluster is not a timer.

### 6.2 Mechanism

1. IDM loads `Crypt32.dll` and caches the handle in a global.
2. It resolves `CertFindChainInStore` or `CertGetCertificateChain` and caches the pointer.
3. A worker thread calls the cached pointer during HTTPS work.
4. A destructor or certificate path calls `FreeLibrary`.
5. The unload lands while the worker is inside the module, and the next fetch faults.

### 6.3 Find the chain

1. Search for UTF-16 `Crypt32.dll`. In 6.43 it is at RVA `0x30F888`.
2. Xref it to `LoadLibraryW` or `LoadLibraryA`. The return value is stored in a global.
3. Xref the certificate API name to `GetProcAddress`; that pointer goes to another global.
4. Find indirect calls through that global.
5. Find `FreeLibrary` calls that use the handle.
6. Log `LoadLibrary`, `GetProcAddress`, `FreeLibrary`, and `LdrUnloadDll` with thread ids and stacks. `LdrUnloadDll` may be called below `FreeLibrary` or by a certificate path that manages the module itself.

### 6.4 Fix 1: remove the free

In 6.43 the free is:

```text
50 FF 15 C0 84 6D 00  ->  90 90 90 90 90 90 90      file 0x478B1
```

Seven bytes: `push eax` plus the six-byte indirect call. The stack is unchanged because both are removed together. If the sequence differs, remove the whole argument setup and call; never leave a stray push.

### 6.5 Fix 2: entry-point resident reference

If several paths unload the module, hold one reference for the life of the process. Add a stub, make it the entry point, load the module, never free, then jump to the original entry.

The 6.43 stub, 35 bytes at file `0x2D6A4C`, RVA `0x2D764C`:

```text
E8 00 00 00 00        call $+5
58                    pop eax
2D 51 76 2D 00        sub eax, 0x2D7651
89 C3                 mov ebx, eax
60                    pushad
8D 83 88 F8 30 00     lea eax, [ebx+0x30F888]
50                    push eax
8B 93 EC 83 2D 00     mov edx, dword ptr [ebx+0x2D83EC]
FF D2                 call edx
61                    popad
E9 7D D7 FA FF        jmp 0x284DEC
```

`AddressOfEntryPoint` at file `0x120` becomes `4C 76 2D 00`, RVA `0x2D764C`. The stub computes the image base from its own return address, so it survives ASLR. The jump returns to the original entry RVA `0x284DEC`.

Two independent replacement checks:

1. The `sub eax, imm32` immediate must equal the RVA of the instruction after `call $+5`. If it is off by one, the base is wrong and the load faults.
2. The final `jmp rel32` must land on the original entry RVA in the pristine file, not on a jump thunk.

If you cannot change `AddressOfEntryPoint`, overwrite the entry with `E9 <rel32>` to the stub, copy the stolen bytes into the stub, and end with `jmp entry + stolen_length`. Never jump back to `entry`, which now contains the jump to the stub.

### 6.6 Verify the module lifetime

- Launch from the install path with `ExePath` matching.
- Enumerate modules with a 32-bit Toolhelp32 loop (`TH32CS_SNAPMODULE32`). A 64-bit module read shows the WOW64 host and misses crypt32.
- Confirm `crypt32.dll` before any download.
- Perform an HTTPS download.
- Confirm it is still present after the download and after any `LdrUnloadDll`.
- Sample at 60, 300, and 600 seconds, then after 40 minutes in the tray.
- Confirm no WER `CRYPT32.dll_unloaded` for the pid.

```c
HANDLE snap = CreateToolhelp32Snapshot(TH32CS_SNAPMODULE | TH32CS_SNAPMODULE32, pid);
MODULEENTRY32 me;
me.dwSize = sizeof(me);
BOOL found = FALSE;
for (BOOL ok = Module32First(snap, &me); ok; ok = Module32Next(snap, &me)) {
    if (_stricmp(me.szModule, "crypt32.dll") == 0) { found = TRUE; break; }
}
CloseHandle(snap);
```

Compile and run that loop as a 32-bit process.

### Gate 6

- `crypt32.dll` present before and after an HTTPS download.
- No WER `CRYPT32.dll_unloaded` for the pid.
- Ten minute tray soak with no exit.

---

## 7. Phase 7: helper

`IDMGrHlp.exe` is a separate 32-bit MFC executable. `IDMan.exe` launches it, and it also starts directly. It shows the periodic fake-serial dialogs.

### 7.1 Find the helper dialogs

1. Open `IDMGrHlp.exe` in the disassembler.
2. Xref every `MessageBoxA` and `MessageBoxW` call.
3. Find the call sites that build the fake-serial strings.
4. In 6.43 the two call sites are at file `0x52A1` and `0x52C8`.

If the helper uses a custom dialog resource, apply the title or control check from phase 4.1 to its procedure.

### 7.2 Patch the helper

Each site is a six-byte indirect call:

```text
FF 15 <IAT MessageBoxA>  ->  31 C0 90 90 90 90
```

`MessageBoxA` is stdcall and normally cleans its arguments. Removing the call also removes the cleanup. If arguments are pushed immediately before the call, add `add esp, n` or use a `ret n` gadget. In 6.43 there are no pending arguments at either site.

A safer generic alternative is to patch the function that builds the dialog to `31 C0 C3` when several call sites share it.

### 7.3 Verify the helper

- Run `IDMGrHlp.exe` directly. It exits 0 and shows no window.
- Run IDMan long enough for the helper to start. No helper dialog appears.

### Gate 7

- Helper exits 0 with no window.
- No fake-serial dialog after 15 minutes of IDM uptime.

---

## 8. Phase 8: build the artifact

### 8.1 Manifest schema

```json
{
  "target": "Internet Download Manager 6.43 build 18, 32-bit IDMan.exe",
  "pristine_sha256": "A705C0154FAFC7CD509DECF165CB6F6C050B6521B40ADB6F730DD827C86051C7",
  "expected_sha256": "98D9E4085759E13836E3063C5E11FA75770A974582FA8890F39A290A83ECE260",
  "patches": [
    {
      "name": "serial_validator",
      "offset": "0x5A830",
      "original": "55 8B EC",
      "patch": "B0 01 C3"
    }
  ]
}
```

Rules:

- `offset` is a file offset, never an RVA or VA.
- Always include `original`. The patcher refuses a mismatch, which catches a wrong build.
- `patch` is the complete replacement. The patcher does not pad, so include every byte you intend to write.
- Patches must not overlap. Overlap usually means a cave range and a code site disagree about the same bytes.
- `expected_sha256` is a local regression check. It is not a build identity across machines with different patch sets.
- Do not list the checksum field. The patcher recomputes it.

### 8.2 Apply the manifest

```text
python tooling/patch.py manifest/6.43b18.json pristine/IDMan.exe build/IDMan.exe
```

The tool prints every applied patch, the checksum, and the input and output hashes. `PASS` means the output matches `expected_sha256`.

### 8.3 Generate a manifest from a diff

1. Keep the pristine copy.
2. Build the patched file by any means.
3. Diff pristine against patched:

```python
a = open("pristine/IDMan.exe", "rb").read()
b = open("build/IDMan.exe", "rb").read()
i = 0
while i < len(a):
    if a[i] != b[i]:
        j = i
        while j < len(a) and a[j] != b[j]:
            j += 1
        print("0x%X  %s  ->  %s" % (i, a[i:j].hex(" "), b[i:j].hex(" ")))
        i = j
    else:
        i += 1
```

4. Group the runs into semantic patches. Merge fragments inside a cave into one cave patch; the diff splits them wherever the patched bytes happen to be zero.
5. Exclude the checksum field.
6. Re-apply the manifest to the pristine file and compare the output hash with the hand-built file. They must be identical.

### 8.4 Checksum

The checksum field is at `e_lfanew + 4 + 20 + 0x40`, which is file `0x150` for a standard PE32 header. Compute it from `e_lfanew`; do not hardcode `0x150` in a tool that must work on other builds.

```python
def pe_checksum(data, checksum_offset):
    total = 0
    for i in range(0, len(data), 2):
        if checksum_offset <= i < checksum_offset + 4:
            continue
        word = data[i]
        if i + 1 < len(data):
            word |= data[i + 1] << 8
        total += word
        total = (total & 0xFFFF) + (total >> 16)
    total = (total & 0xFFFF) + (total >> 16)
    return (total + len(data)) & 0xFFFFFFFF
```

The Windows loader does not normally verify the checksum, but IDM's self-check may. A correct checksum removes one variable from every later investigation.

### 8.5 Reproduce and compare

The manifest is only trustworthy when it reproduces the verified binary byte for byte:

```text
python tooling/patch.py manifest/6.43b18.json pristine/IDMan.exe build/IDMan.exe
```

Expected for this repository's 6.43 build 18 manifest:

```text
input  A705C0154FAFC7CD509DECF165CB6F6C050B6521B40ADB6F730DD827C86051C7
output 98D9E4085759E13836E3063C5E11FA75770A974582FA8890F39A290A83ECE260
PASS
```

If the output differs, the manifest is missing a patch, has an extra patch, or applied one at the wrong offset. Debug it on the copy, never on the live install.

### Gate 8

- Manifest applies cleanly to the pristine file.
- Output hash equals the recorded verified hash for that build and patch set.
- Checksum recomputed at the correct field.
- No overlapping patches.

---

## 9. Phase 9: install and verify

### 9.1 Install

1. Kill every IDMan and IDMGrHlp process.
2. Back up `IDMan.exe` and `IDMGrHlp.exe` outside the install directory.
3. Write the patched files to the install directory. `Program Files` needs elevation.
4. Set `ExePath` to the exact installed path.
5. Set the autostart entry to the installed path, quoted:

```powershell
Set-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name IDMan `
  -Value '"C:\Program Files (x86)\Internet Download Manager\IDMan.exe" /onboot'
```

An unquoted path with spaces fails at logon. A leftover autostart entry pointing at a workspace copy is a common reason the registration window returns after a reboot.

6. Launch from the installed path. Do not double-click a copy in a temp directory.

### 9.2 Verification matrix

| Check | Pass condition |
|---|---|
| Hash | Installed file equals the manifest output hash |
| Status | Phase 2 probe returns 0 |
| About | Registered, no trial counter |
| Registration menu | No window, no warning, no licensed-to |
| Download | Only `Download File Info` and `Download complete` |
| Buy page | No `buy2.html` or `buy_idm2.html` process |
| Update | `LastCheckQU` does not change during a normal launch |
| Tray | Close hides the window, tray icon remains, process alive |
| Soak | Alive after 40 minutes in the tray |
| Crypt32 | 32-bit module list contains `crypt32.dll` after HTTPS work |
| WER | No `Application Error 1000` for the pid |
| Helper | `IDMGrHlp.exe` exits 0 with no window |
| Transfer | A submitted URL reaches IDM and downloads |

`tooling/gate.ps1` automates the static checks, the launch, the tray check, and an optional transfer test:

```powershell
powershell -File tooling/gate.ps1 `
  -Exe "C:\Program Files (x86)\Internet Download Manager\IDMan.exe" `
  -AliveSeconds 20 -TraySeconds 15 `
  -TransferUrl "https://example.com/file.zip"
```

### 9.3 Browser handoff

The browser extension hands a URL to a running IDM. If IDM is not running, the handoff fails and the extension reports:

```text
Cannot transfer the download to IDM
Error 0x80010108
```

`0x80010108` is `RPC_E_DISCONNECTED`: the COM automation server that the extension expects to talk to is gone. It is a symptom of IDM not running, not a browser problem. Fix the startup path. Do not reinstall the extension.

Test the handoff without the browser:

```text
"C:\Program Files (x86)\Internet Download Manager\IDMan.exe" /d "https://example.com/file.zip"
```

With IDM running, this opens `Download File Info` against the running instance. With IDM stopped, it starts a new instance first. Both must work, because the extension uses the same entry point.

### 9.4 Failure decision tree

| Symptom | Most likely cause | Check |
|---|---|---|
| Exit in under 1 second, code 0 | Another IDMan is already running | `Get-Process IDMan` |
| Exit in under 1 second, code 2 | `ExePath` mismatch, or the registration dialog was dismissed and the exit path ran | Compare `ExePath` with the launched path; probe for `EndDialog` then exit |
| Registration window at startup | Status probe returns non-zero, usually 6 | Re-run phase 2, patch that code |
| Fake-serial warning after a download | Warning function or call sites unpatched | Phase 4.2 |
| Licensed-to dialog | Licensed-to call unpatched | Phase 4.3 |
| Buy page opens | URL builder or `ShellExecute` unpatched | Phase 4.4 |
| Update check runs | Check function or timer unpatched | Phase 4.5 |
| Process exits in the tray after seconds or minutes | Unpatched timer or `PostQuitMessage`/`ExitProcess` site | Phase 5, then re-probe |
| Crash after HTTPS | crypt32 free still present, or entry stub wrong | Phase 6 |
| `CRYPT32.dll_unloaded` in WER | crypt32 not resident | Phase 6.4 or 6.5 |
| Module list lacks crypt32 but the app works | 64-bit module read on a 32-bit process | Use 32-bit Toolhelp32 |
| `0x80010108` in the browser | IDM is not running | Phase 9.3, fix startup |
| Soak ends when a second IDMan starts | Single instance | Kill all before the soak |
| Patcher reports overlap | Two patches cover the same bytes | Split or reorder |
| Crash after a call patch | Stack cleanup wrong | Check cdecl vs stdcall, use a `ret n` gadget |

---

## 10. Phase 10: version drift

Every layer has stable anchors and unstable offsets. Anchors are strings, imports, registry names, format constants, dialog titles, status codes, and call shapes. Unstable are addresses, register allocation, function order, and compiler prologues.

| Layer | Stable anchor | 6.43 build 18 (file offsets) | Re-find method |
|---|---|---|---|
| Version | File version, `idmvers` | `v6.43b18` | File resource plus registry |
| Serial validators | `Serial`, length 23, hyphens at 5, 11, 17 | `0x5A4B0`, `0x5A830` | Xref the registry string and the length constants |
| Status dispatcher | One caller at startup, returns small codes | `0x4FA30` body, codes at `0x50083`, `0x50C1C`, `0x50CFB`, `0x50D5C`, `0x50DBD` | Probe the return value, then locate the `mov eax, imm32` |
| Registration dialog | Title `Internet Download Manager Registration` | proc `0x250B62`, cave `0x2D6A80` | Resource list, title xref, `DialogBoxParamW` |
| Message wrapper | `IDM_emc_` caption, runtime decode | `0x6C9C0`, callers `0x74899` and others | Hook `MessageBoxW`, read the caller offset |
| Warning | Return 0 suppresses the message | `0x73B60`, `0x93B5F`, `0x74E84` | Xref the wrapper callers |
| Licensed-to | Formatted confirmation | `0x893A6` | Xref the formatter or the call |
| Buy page | `buy`, `buy2.html`, `ShellExecute` | `0x7C1A0`, `0x7EA43`, `0x914DD` | Xref the URL and the shell call |
| Update | `LastCheckQU` | `0x55DD0` | Xref the registry value |
| Timers | `SetTimer`, interval immediates | `0x6C073`, `0x8DA76`, `0x76666` | Enumerate `SetTimer`, inspect `WM_TIMER` |
| Quit | `PostQuitMessage` IAT | `0x14E902`, `0xB7E27`, `0xE21BE`, `0xE2647`, `0x25F5A0` | Xref the IAT slot |
| Exit | `ExitProcess` IAT | `0x101D4`, `0x4D006`, `0x6640B`, `0x6C0CF`, `0x120D5C` | Xref the IAT slot |
| Tray | `WM_CLOSE`, `ShowWindow` | `0x88C15`, cave `0x896F4` | Window procedure `WM_CLOSE` case |
| Crypt32 | `Crypt32.dll`, cert APIs | load `0x30F888`, free `0x478B1`, stub `0x2D6A4C` | Xref the string and `FreeLibrary` |
| Helper | `IDMGrHlp.exe`, `MessageBox` | `0x52A1`, `0x52C8` | Xref the helper dialogs |
| Checksum | PE optional header | field `0x150` | `e_lfanew + 4 + 20 + 0x40` |

### 10.1 What usually changes

- Every address and offset.
- Function order and inlining. A validator may be inlined into its caller.
- Register allocation. A cached handle may move.
- Dialog resource ids and control order.
- String addresses and occasional wording.
- Timer ids and intervals.
- The compiler prologue and epilogue.

### 10.2 If the binary is packed

Check sections, entropy, imports, and entry point. A packed binary has few imports, a writable and executable section, and a stub at the entry. Unpack before analysis:

1. Run it in a VM under a debugger.
2. Break after the unpacking stub reaches the original entry.
3. Dump the process image with a PE dump tool.
4. Rebuild the import table if needed.
5. Verify the dumped image runs.

IDM's standard builds are not packed. A third-party repack may change that.

### 10.3 If the build is 64-bit

Treat it as a new target. The layer model holds; the byte patterns and cave code do not.

- 64-bit debugger and disassembler.
- First four arguments in `RCX`, `RDX`, `R8`, `R9`; stack arguments start at `[rsp+0x28]`.
- Dialog procedure arguments are in registers, not at `[ebp+0xC]`.
- The entry stub must preserve the 64-bit convention and load the 64-bit module.
- The module list is native, so 64-bit enumeration is correct.

### 10.4 If the UI is rewritten

Do not rely on the title length. Find the dialog by control text (`Serial`, `First Name`, `Last Name`, `Email`) or by the resource id used at the creation call. In the cave, use `GetDlgItem` with a known control id, or `GetWindowTextW` and a full compare.

### 10.5 If crypt32 is loaded differently

The load may be delayed until the first HTTPS operation, or use `LoadLibraryExW` with flags. Log `LoadLibraryW`, `LoadLibraryExW`, `GetProcAddress`, `FreeLibrary`, and `LdrUnloadDll` with return values and stacks. If a delay-load helper loads it, patch the delay-load call or the free, not the visible `LoadLibrary`.

### 10.6 If the helper is merged

If `IDMGrHlp.exe` disappears and its dialogs move into `IDMan.exe`, search the main executable for the same call shapes and patch those sites with the same six-byte skip.

### 10.7 Validating a new build

1. Record version and baseline behavior.
2. Probe the status code before patching.
3. Patch one layer, then run that layer's gate.
4. Build the manifest, reproduce the hash, then install.
5. Run the full matrix, including a ten minute tray soak.

---

## Appendix A: verified 6.43 build 18 patch set

`manifest/6.43b18.json` contains 38 patches. The code site list, by purpose:

| Group | Patches |
|---|---|
| Entry | `entry_point_rva`, `entry_stub` |
| Status | `status_counterfeit`, `status_trial_expired`, `online_registration_branch`, `timer_registered_path` |
| Validators | `name_validator`, `serial_validator` |
| UI | `registration_dialog_proc`, `dialog_cave`, `warning_function`, `fake_serial_warning_1`, `fake_serial_warning_2`, `licensed_to_call`, `dialog_wrapper_call` |
| Buy and update | `buy_page_builder`, `buy_page_timer`, `buy_page_shellexec`, `update_check` |
| Lifecycle | `exitprocess_1` to `exitprocess_5`, `postquit_site_2` to `postquit_site_4`, `postquit_tray_destroy`, `postquit_thunk`, `exit_timer_10s`, `exit_timer_32s`, `exit_timer_branch`, `registration_timer_12s`, `timer21_arm_a`, `timer21_arm_b`, `wm_close_redirect`, `tray_cave` |
| Crypt32 | `crypt32_free` |

Hashes:

```text
pristine  A705C0154FAFC7CD509DECF165CB6F6C050B6521B40ADB6F730DD827C86051C7
output    98D9E4085759E13836E3063C5E11FA75770A974582FA8890F39A290A83ECE260
checksum  0x00645141 at file 0x150
size      6,517,616 bytes
```

The helper `IDMGrHlp.exe` for the same build:

```text
file offsets 0x52A1, 0x52C8   FF 15 <MessageBoxA>  ->  31 C0 90 90 90 90
sha256       F5E7360A0C376247507218AC92392BD8B71AF703...
```

Verify the helper hash against your own pristine copy; the manifest does not cover it because the helper changes independently of `IDMan.exe`.

## Appendix B: tooling

| File | Use |
|---|---|
| `tooling/patch.py` | Apply a manifest, recompute the checksum, verify `expected_sha256` |
| `tooling/hook-status.py` | Spawn under Frida, log the status code, dialogs, exits |
| `tooling/hook-status.js` | The Frida probe body, editable for extra hooks |
| `tooling/gate.ps1` | Static manifest check plus launch, tray, WER, optional transfer |
| `manifest/6.43b18.json` | The verified 38-patch manifest |

## Appendix C: byte and API index

| Target | Pattern | Notes |
|---|---|---|
| Function prologue | `55 8B EC` or `8B FF 55 8B EC` | MSVC x86 |
| Return false | `31 C0 C3` | `xor eax, eax ; ret` |
| Return true in AL | `B0 01 C3` | `mov al, 1 ; ret` |
| Return true in EAX | `31 C0 FF C0 C3` | `xor eax, eax ; inc eax ; ret` |
| Skip a six-byte indirect call | `31 C0 90 90 90 90` | Returns 0 |
| Remove a push and call | `90` x 7 | Push plus six-byte call |
| `PostQuitMessage` call | `FF 15 <IAT>` | Patch `58 90 90 90 90 90` |
| `PostQuitMessage` jump | `FF 25 <IAT>` | Patch `C3 90 90 90 90 90` |
| `ExitProcess` call | `FF 15 <IAT>` | Patch to a `ret n` gadget |
| `LoadLibraryW` | `FF 15 <IAT>` | Stdcall, one argument |
| `GetProcAddress` | `FF 15 <IAT>` | Stdcall, two arguments |
| `FreeLibrary` | `FF 15 <IAT>` | Stdcall, one argument |
| 20 minute timer | `68 80 4F 12 00` | 1,200,000 ms |
| 10 minute timer | `68 C0 27 09 00` | 600,000 ms |
| 3 minute timer | `68 20 BF 02 00` | 180,000 ms |
| 32 second timer | `68 00 7D 00 00` | 32,000 ms |
| 12 second timer | `68 E0 2E 00 00` | 12,000 ms |
| 10 second timer | `68 10 27 00 00` | 10,000 ms |
| INFINITE interval | `68 FF FF FF 7F` | Replacement for any exit interval |
| Serial length | `83 F8 17` or `3D 17 00 00 00` | 23 decimal |
| Hyphen check | `80 78 05 2D` | `cmp byte ptr [eax+5], '-'` |

## Appendix D: discovery worksheet

Copy and fill before patching:

```json
{
  "build": {
    "file_version": "",
    "idmvers": "",
    "idman_sha256": "",
    "size": 0
  },
  "runtime": {
    "status_dispatcher_rva": "",
    "status_code": null,
    "status_evidence": "",
    "message_wrapper_rva": "",
    "dialog_proc_rva": "",
    "exit_sites": [],
    "postquit_sites": [],
    "crypt32_free_site": ""
  },
  "patches": {
    "status_sites": [],
    "ui_sites": [],
    "lifecycle_sites": [],
    "crypt32_sites": []
  },
  "verification": {
    "gate_log": "",
    "output_sha256": "",
    "soak_minutes": 0,
    "transfer_ok": false
  }
}
```
