# Internet Download Manager: generic crack playbook

This is a method for cracking Internet Download Manager 6.x, not a fixed list of offsets. The worked example is 6.43 build 18, but every section explains how to find the same decision point in a different build.

The goal is a local build that:

- reports a registered state,
- shows no registration, counterfeit, licensed-to, buy-page, or update UI,
- stays alive in the tray,
- keeps crypt32 resident during HTTPS work,
- runs the helper without dialogs.

Work on a copy. Keep a pristine backup and a patch manifest. Record every offset and byte you change, because the next build will move them.

## 0. How to use this playbook

1. Read sections 1 to 3 to understand the target and the crack surface.
2. For a new build, run the discovery workflow in sections 4 to 8. Do not copy offsets from the worked example.
3. For 6.43 build 18, section 12 is a reference map. Use it only after you have identified that exact build.
4. Write every patch into a manifest. Section 10 contains a generic patcher that applies the manifest and recomputes the PE checksum.
5. Run the verification matrix in section 13. A patch is not done until the matrix passes.

The central rule: patch decisions, not bytes. A byte sequence is a symptom of a decision. If you understand the decision, you can find it again after the compiler moves it.

## 1. Target, lab, and baseline

### 1.1 Files and architecture

| File | Role |
|---|---|
| `IDMan.exe` | Main 32-bit native application. License checks, UI, timers, downloads, crypt32 use. |
| `IDMGrHlp.exe` | Separate 32-bit MFC helper. Shows periodic fake-serial dialogs. |
| `IDMBroker.exe` | Optional broker in some builds. Check whether it participates in license or update checks. |

Determine the architecture before opening a disassembler:

```text
PE32, 32-bit x86, image base 0x400000 in the 6.43 build.
```

A 64-bit debugger will show the process, but its module list is the WOW64 host list. Use a 32-bit debugger or a 32-bit Toolhelp32 enumerator when you need the real module list.

### 1.2 Version identification

Use at least two independent sources:

- File version resource: `IDMan.exe` properties, or `pefile` `VS_FIXEDFILEINFO`.
- Registry `HKCU\Software\DownloadManager\idmvers`, for example `v6.43b18 Trial`.
- The About dialog.
- The installer name and build number.

Record the version string exactly. Two builds with the same marketing version can have different offsets.

### 1.3 Tooling

| Tool | Use |
|---|---|
| IDA Pro or Ghidra | Static analysis, xrefs, decompiler, jump tables. |
| x64dbg (32-bit) | Breakpoints, memory patches, stack inspection, module list. |
| Detect It Easy, PE-bear, `pefile` | Headers, sections, imports, resources, entry point, checksum. |
| `strings`, `strings -el` | ASCII and UTF-16LE strings. |
| Process Monitor | Registry, file, and network behavior. |
| API Monitor | `RegQueryValue`, `DialogBoxParam`, `MessageBox`, `SetTimer`, `LoadLibrary`, `FreeLibrary`, `ShellExecute`. |
| Frida | Runtime hooks, module load/unload, thread stacks, argument values. |
| Windows Event Viewer | WER Application Error records, faulting module and offset. |

### 1.4 Lab baseline

Before patching, record the unmodified behavior:

1. Launch `IDMan.exe` from its install path.
2. Read `idmvers` and open the About dialog.
3. Open the Registration dialog from the menu.
4. Add a small HTTP download and a small HTTPS download.
5. Close the main window to the tray.
6. Sample the process and the 32-bit module list at 5, 60, 300, and 600 seconds.
7. Note every dialog title and every visible string.
8. Export the registry key.

The HTTPS download is important: it loads `crypt32.dll` and exercises the module lifetime path. A tray soak without an HTTPS download can miss the crash entirely.

### 1.5 Address conversion

The disassembler shows VAs and RVAs; the patcher uses file offsets. Convert with the section table:

```text
file_offset = rva - section.VirtualAddress + section.PointerToRawData
rva = file_offset - section.PointerToRawData + section.VirtualAddress
va = image_base + rva
```

Find the section that contains the RVA. In the 6.43 build the `.text` section maps RVA `0x1000` to file `0x400`, so the delta is `0xC00`, but do not hardcode the delta. Read the section table:

```python
import pefile
pe = pefile.PE("IDMan.exe")
for section in pe.sections:
    name = section.Name.decode(errors="ignore").rstrip("\x00")
    print(name, hex(section.VirtualAddress), hex(section.PointerToRawData), hex(section.Misc_VirtualSize))
```

Check the section characteristics before writing a cave. A code cave must be in a section with `IMAGE_SCN_MEM_EXECUTE`.

## 2. The crack surface

IDM has eight decision layers. Patch the layer that produces the behavior you want to remove; do not patch a shared function unless you understand every caller.

| Layer | What it decides | Generic target |
|---|---|---|
| Registry identity | Serial, name, email, display version, launched path | Correct values and a synthetic serial |
| Validators | Whether the name and serial are syntactically acceptable | Return true, or bypass the caller |
| Status dispatcher | Registered, trial, counterfeit, blocked, expired, exit | Force the registered path, or suppress the UI |
| UI | Registration dialog, warning, licensed-to, buy page, update | Hide or skip the specific dialog or call |
| Lifecycle | Timers, tray close, `PostQuitMessage`, `ExitProcess` | Keep the message loop and process alive |
| Module lifetime | `crypt32.dll` load, use, unload | Keep one reference resident |
| Helper | Periodic fake-serial dialogs from `IDMGrHlp.exe` | Skip the `MessageBox` calls |
| Integrity | PE checksum and self-check | Recompute the checksum after patching |

### 2.1 Patch strategy

- Smallest useful patch: if the only symptom is a warning, patch the warning call, not the whole license function.
- Call-site patch over function patch: a function may be shared by the About dialog, the registration dialog, and the download path.
- Stack discipline: know whether the call is cdecl or stdcall, and whether the caller cleans the arguments.
- Preserve registers: a cave or stub that runs inside a dialog procedure must preserve registers the original code expects.
- Verify each layer alone: patch the license UI, test; patch the lifecycle, test; patch crypt32, test. Do not stack unverified changes.

## 3. First contact: strings, imports, and registry

### 3.1 Strings

Search both ASCII and UTF-16LE:

```text
strings -a IDMan.exe
strings -el IDMan.exe
```

High-value strings:

| String | Layer |
|---|---|
| `Serial`, `FName`, `LName`, `Email` | Registry identity |
| `Internet Download Manager Registration` | Registration dialog title |
| `fake Serial Number`, `counterfeit` | Warning |
| `This product is licensed to` | Licensed-to confirmation |
| `Trial`, `days left`, `expired` | Status display |
| `buy`, `buy2.html`, `buy_idm2.html` | Buy page |
| `LastCheckQU`, `update` | Update check |
| `main IDM executive file is damaged` | Integrity verdict |
| `Crypt32.dll`, `CertFindChainInStore`, `CertGetCertificateChain` | Module lifetime |
| `IDMGrHlp.exe` | Helper |

In IDA or Ghidra, use `Alt+B` or the string list, then xref each string to code. A string xref is the fastest way to find the surrounding function.

### 3.2 Imports

Map the import table and find the call sites for these APIs:

```text
RegOpenKeyExW, RegQueryValueExW, RegSetValueExW
DialogBoxParamW, CreateDialogParamW, EndDialog
MessageBoxW, MessageBoxA
SetTimer, KillTimer
PostQuitMessage, ExitProcess
ShellExecuteW, ShellExecuteA
ShowWindow, PostMessageW
LoadLibraryW, LoadLibraryA, GetProcAddress, FreeLibrary
GetWindowTextLengthW, GetWindowTextW
CreateToolhelp32Snapshot, Module32First, Module32Next
```

A call site is usually `FF 15 <IAT slot>` for an import. In a 32-bit build, the IAT slot is a VA in the `.idata` or `.rdata` range. Xref the slot to find every caller.

### 3.3 Registry

The license and identity values live under:

```text
HKCU\Software\DownloadManager
```

| Value | Type | Role |
|---|---|---|
| `Serial` | REG_SZ | 23 characters, hyphens at positions 5, 11, 17 |
| `FName` | REG_SZ | First name |
| `LName` | REG_SZ | Last name |
| `Email` | REG_SZ | Email |
| `idmvers` | REG_SZ | Display version, for example `v6.43b18 Trial` or `v6.43b18 Full` |
| `ExePath` | REG_SZ | The exact image path IDM expects to run from |
| `LastCheckQU` | REG_SZ or REG_DWORD | Last update check timestamp |

The `ExePath` gate is a common source of confusion. If the launched image path does not match `ExePath`, IDM exits silently in about 0.12 seconds. Set `ExePath` to the exact path you launch, including the drive letter and the `Program Files (x86)` spelling.

Use a random synthetic serial such as `A7K2M-9Q4XZ-3V8NB-6T1WP`. The well-known `12345-67890-12345-67890` is blacklisted in current builds and triggers the licensed-to path even when the UI is patched.

Set the registry values before the first patched launch:

```powershell
$key = 'HKCU:\Software\DownloadManager'
New-Item -Path $key -Force | Out-Null
Set-ItemProperty -Path $key -Name Serial -Value 'A7K2M-9Q4XZ-3V8NB-6T1WP'
Set-ItemProperty -Path $key -Name FName  -Value 'Test'
Set-ItemProperty -Path $key -Name LName  -Value 'User'
Set-ItemProperty -Path $key -Name Email  -Value 'test@example.com'
Set-ItemProperty -Path $key -Name ExePath -Value 'C:\Program Files (x86)\Internet Download Manager\IDMan.exe'
```

### 3.4 Build an anchor table

Before patching, fill a table like this:

| Anchor | Address or offset | How found | Confidence |
|---|---|---|---|
| Serial validator 1 | | xref `Serial` string | |
| Serial validator 2 | | nearby function | |
| Status function | | caller of validators | |
| Status switch | | jump table after status call | |
| Registration dialog proc | | `DialogBoxParamW` xref | |
| Warning function | | xref `fake Serial Number` | |
| Licensed-to call | | xref `This product is licensed to` | |
| Buy-page call | | xref `buy` or `ShellExecute` | |
| Update check | | xref `LastCheckQU` | |
| `PostQuitMessage` sites | | IAT xrefs | |
| `ExitProcess` sites | | IAT xrefs | |
| Crypt32 load | | xref `Crypt32.dll` | |
| Crypt32 free | | xref cached handle | |
| Helper dialogs | | `MessageBox` xrefs in helper | |

The rest of this playbook fills the rows.

### 3.5 Code caves

A code cave is a run of unused bytes inside an executable section. `CC` (`int3`) padding and `00` padding are common. Use a cave for the dialog stub, the entry stub, or a trampoline.

1. Find a run of at least the stub size inside `.text`.
2. Confirm that no xref points into the run. In IDA or Ghidra, check the address and the surrounding function.
3. Prefer `CC` padding. `00` bytes decode as `add [eax], al` if execution reaches them, but they are usable as cave data once you overwrite them completely.
4. Keep the cave in the same section so it is executable and the RVA mapping is simple.
5. If you add a new section, set `IMAGE_SCN_CNT_CODE | IMAGE_SCN_MEM_EXECUTE | IMAGE_SCN_MEM_READ`, update `SizeOfImage`, and expect integrity checks to notice the new section.

The 6.43 build uses `0x2D6A4C` for the entry stub and `0x2D6A80` for the dialog cave. Both are in `.text` padding.

## 4. License validation

### 4.1 Find the validators

Start from the registry value names. A validator or status reader usually:

1. Opens `HKCU\Software\DownloadManager`.
2. Queries `Serial`, `FName`, `LName`, and `Email`.
3. Checks the serial length and hyphen positions.
4. Returns a boolean or a small status code.

In the disassembler, xref the UTF-16 string `Serial` to the `RegQueryValueExW` call. The function around that call is a validator or a status reader. Repeat for `FName`, `LName`, and `Email`. If all four are read in one function, that function is the status reader.

If the strings are obfuscated or built dynamically, set a breakpoint on `RegQueryValueExW` and log the value name and output buffer for each call. The license values appear at startup.

Look for these constants:

| Constant | Meaning |
|---|---|
| `0x17` (23) | Serial length |
| `0x2D` (`-`) | Hyphen character |
| `5`, `0xB` (11), `0x11` (17) | Hyphen positions |
| `0x100` or `0x104` | Buffer size for `RegQueryValueExW` |

A typical validator prologue is `55 8B EC` or `8B FF 55 8B EC`. The return value is in `AL` or `EAX`.

If the serial format changes, find the new length and separator checks, or patch the validator to return true and use a value that the rest of the code accepts. If the validator is inlined into the status reader, patch the status function or the UI instead of trying to isolate the validator.

### 4.2 Patch the validators

If a validator returns a boolean in `AL`:

```text
B0 01 C3        mov al, 1 ; ret
```

If it returns an `int` in `EAX`:

```text
31 C0 FF C0 C3  xor eax, eax ; inc eax ; ret
```

If the function is `__stdcall` with arguments, a bare `ret` is wrong. Use `ret n` where `n` is the argument byte count, or patch the return-value instruction instead. Check the caller's cleanup:

```text
call validator
add esp, 8
```

If the caller uses `add esp`, the function is cdecl, and `ret` is correct. If the caller does not clean the stack, the function is stdcall, and you need `ret n`.

### 4.3 Find the status dispatcher

The status dispatcher calls the validators and returns a code. In 6.43 the codes are:

| Status | Meaning |
|---:|---|
| 0 | Registered |
| 1 | Counterfeit warning |
| 2 | Blocked serial details |
| 3 | Exiting |
| 6 | Trial expired: registration dialog at startup, then the "not been registered for 15 days" warning and exit |
| 7 | Empty or unreadable serial |
| 10 | Serial used on another computer |
| 12 | Blocked serial |

Codes 6, 7, and 12 were read from the dispatcher at runtime, not from the source. Confirm each code with an `onLeave` hook on the dispatcher return value before patching it: the day counter that drives code 6 is state, so a build that returns 3 on one machine can return 6 on another with the same binary.

The caller switches on the status through a jump table:

```text
call status_function
cmp eax, 0xA
ja default
jmp dword ptr [eax*4 + table]
```

Find the table and map each entry to a case. Each case either shows a dialog, opens a buy page, or exits.

### 4.4 Patch the status path

Three strategies, from least to most invasive:

1. Patch the UI that the status case shows. This is the safest when the status also feeds the About display.
2. Patch the switch so the registered case is always taken. Replace the jump table entries or the initial comparison.
3. Force the status function to return 0:

```text
31 C0 C3        xor eax, eax ; ret
```

Test the About dialog after strategy 3. Some builds use the same status for the display string, so forcing 0 can show `Trial` even though the warning is gone. In 6.43 this happened; the robust build keeps the status function original and suppresses the UI.

A fallback is to patch the counterfeit immediate:

```text
B8 03 00 00 00  ->  B8 00 00 00 00
```

This changes only the counterfeit return, not the whole status function.

The same treatment applies to every non-zero return that the machine can produce. Patch the immediate at the `mov eax, imm32` that feeds the shared epilogue, not the caller. In the 6.43 build the trial-expired return is:

```text
B8 06 00 00 00  ->  31 C0 90 90 90
```

Patch only the code the running build actually returns. A binary that passes a static byte check can still show the registration dialog if the machine returns 6 and only 3 was patched. Hook the dispatcher, read the value, patch that value.

### 4.5 Verify the license layer

- `idmvers` changes from `Trial` to `Full`.
- The About dialog shows the registered state.
- The Registration dialog does not show a counterfeit warning.
- A download does not show a fake-serial warning.
- No buy page opens.

## 5. UI suppression

The license layer may still show dialogs even when the validators return true. Suppress the specific UI instead of forcing the whole status machine.

### 5.1 Registration dialog

Find the dialog template and the dialog procedure.

1. List resources with PE-bear, Resource Hacker, or `pefile`.
2. Find the dialog whose title is `Internet Download Manager Registration` or whose controls include `Serial`, `First Name`, `Last Name`, `Email`.
3. Find the `DialogBoxParamW` or `CreateDialogParamW` call that uses the template.
4. The `lpDialogFunc` argument is the dialog procedure. In x86 stdcall, the call site pushes the arguments right to left, so the procedure pointer appears as a `push offset proc` near the call.
5. The procedure prologue is usually `8B FF 55 8B EC` (`mov edi, edi; push ebp; mov ebp, esp`).

The procedure receives:

```text
[ebp+8]   HWND
[ebp+0xC] UINT message
[ebp+0x10] WPARAM
[ebp+0x14] LPARAM
```

`WM_INITDIALOG` is `0x110`.

### 5.2 The title-length cave

A robust way to close only the registration dialog is a small cave that checks the window title length and forwards every other dialog to the original procedure.

At the procedure entry, write a 5-byte jump:

```text
E9 <rel32>      jmp cave
```

The cave does this:

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

`0x26` is 38 decimal, the length of `Internet Download Manager Registration`. If the title changes in a new build, count the new title or replace the length check with a `GetWindowTextW` string compare.

The cave uses `pushad` and `popad` so the original procedure's registers survive. It calls `GetWindowTextLengthW` and `PostMessageA` through the IAT. `PostMessageA(hwnd, WM_CLOSE, 0, 0)` closes the dialog; returning 1 tells Windows the message was handled. `pop_rva` is the RVA of the instruction after the `call $+5`, where `pop ebx` lands. In the 6.43 cave it is `0x2D7698`.

If the dialog title is not stable, use a control ID or a class name instead. Enumerate the dialog's children with `GetDlgItem` and check for a known control.

### 5.3 Warning function

Find the fake-serial warning:

1. Search for `fake Serial Number` or `counterfeit`.
2. Xref the string to the function that builds the message.
3. If the function returns a value, patch its entry:

```text
31 C0 C3        xor eax, eax ; ret
```

4. If the function is void, patch it to `C3` (`ret`).
5. If the string is used directly in a `MessageBoxW` call, patch the call site:

```text
FF 15 <IAT MessageBoxW>  ->  31 C0 90 90 90 90
```

This skips the call and returns 0. `MessageBoxW` is stdcall, so removing the call also removes its argument cleanup. If arguments were pushed immediately before the call, add the matching `add esp, n`, or use a `ret n` gadget that cleans the arguments and returns to the next instruction. In the 6.43 warning sites the arguments are not left on the stack by this patch.

There may be two warning call sites. Patch both, or patch the shared function. If the string is built dynamically and has no direct xref, find the `MessageBoxW` calls in the status case and patch the one that shows a license message.

### 5.4 Licensed-to confirmation

Search for `This product is licensed to`. The string is often formatted with `wsprintfW` and then passed to `MessageBoxW` or a custom dialog.

Patch the call that shows the confirmation:

```text
E8 <rel32>      ->  31 C0 90 90 90
```

or patch the function that builds and shows it. If arguments were pushed immediately before the call, add the matching `add esp, n` or use a `ret n` gadget. If the string is built dynamically, find the `MessageBoxW` or custom dialog call in the download path and patch it. If the dialog is a custom resource, use the same title-length cave technique.

### 5.5 Buy page and update check

Buy page:

- Search for `buy`, `buy2.html`, `buy_idm2.html`, or a URL.
- Xref the string to the URL builder or `ShellExecuteW`.
- Patch the `ShellExecuteW` call to skip, or patch the URL builder to return 0.
- If the URL is built dynamically, inspect the `ShellExecuteW` arguments and patch the call that opens a browser.
- Check the timer path as well; a timer may open the buy page after a delay.

Update check:

- Search for `LastCheckQU`.
- Find the function that reads or writes it.
- Patch the check function to return 0, or patch the call that performs the HTTP request.
- If `LastCheckQU` is absent in a new build, log WinInet or WinHttp calls during startup and patch the check that runs on a timer.
- `Help -> Check for updates` may be a separate manual path. If you want to disable both, patch the shared function, not only the timer.

### 5.6 Verify the UI layer

- Registration menu: no registration window, no warning, no licensed-to.
- About: registered state, no trial counter.
- Download: only the normal `Download File Info` and `Download complete` windows.
- No `buy2.html` or `buy_idm2.html` process.
- `LastCheckQU` does not change during a normal launch.

## 6. Lifecycle: timers, tray, quit, and exit

The UI can be quiet while the process still terminates itself. Treat the lifecycle as a separate layer.

### 6.1 Enumerate timers

Find every `SetTimer` call:

```text
push 0                 ; lpTimerFunc = NULL
push <interval>
push <timer_id>
push <hwnd>
call SetTimer
```

Common intervals:

| Interval | Milliseconds | Immediate |
|---:|---:|---|
| 10 seconds | 10,000 | `0x2710` |
| 12 seconds | 12,000 | `0x2EE0` |
| 32 seconds | 32,000 | `0x7D00` |
| 3 minutes | 180,000 | `0x2BF20` |
| 10 minutes | 600,000 | `0x927C0` |
| 20 minutes | 1,200,000 | `0x124F80` |

If the callback argument is `NULL`, the window procedure receives `WM_TIMER` (`0x113`). Find the `cmp [ebp+0xC], 0x113` case and inspect each timer ID branch.

Do not assume the 20-minute timer is the self-exit. In 6.43 the four 20-minute arms were exonerated; the real exit was the crypt32 unload race. Inspect the case body for `PostQuitMessage`, `ExitProcess`, or a dialog that leads to exit.

### 6.2 PostQuitMessage

Find the `PostQuitMessage` IAT slot and every xref. A call site is usually:

```text
6A 00                 push 0
FF 15 <IAT slot>      call dword ptr [PostQuitMessage]
```

Replace the call with:

```text
58                    pop eax
90 90 90 90 90        nop x5
```

`pop eax` removes the argument that the preceding `push` placed, so the stack depth, return address, and SEH chain stay unchanged. The call is skipped, and the message loop continues. Confirm that the `push 0` is immediately before the call. If the argument is pushed earlier or by a different instruction, use a `ret` gadget instead, or adjust the stack explicitly.

If the site is a tail jump:

```text
FF 25 <IAT slot>      jmp dword ptr [PostQuitMessage]
```

replace it with:

```text
C3 90 90 90 90 90     ret ; nop x5
```

### 6.3 ExitProcess

Find the `ExitProcess` IAT slot and every xref. A direct call site is:

```text
FF 15 <IAT slot>      call dword ptr [ExitProcess]
```

Patch it to a `ret` gadget:

```text
E8 <rel32> 90         call ret_gadget ; nop
```

The `call` pushes a return address; the gadget's `ret` returns to the next instruction. The original argument stays on the stack for the caller's cleanup. This preserves the stack and avoids a hard return from the middle of a function.

Find a lone `C3` in a padding area of the same section and use its VA for the rel32. If the call site has no argument or the caller does not clean the stack, `31 C0 90 90 90 90` may work, but verify the stack after the patch.

### 6.4 Tray close

Find the window procedure's `WM_CLOSE` (`0x10`) case. Patch it to hide the window instead of destroying it:

```text
ShowWindow(hwnd, SW_HIDE)
return 0
```

A cave is usually easier than inlining:

```text
8B 75 08              mov esi, dword ptr [ebp+8]
83 FE 10              cmp esi, 0x10
74 0A                 je close
...
close:
6A 00                 push 0                 ; SW_HIDE
56                    push esi               ; hwnd
FF 15 <ShowWindow>    call dword ptr [ShowWindow]
...
```

In 6.43 the `WM_CLOSE` case at `0x88C15` jumps to a cave at `0x896F4`. The cave calls `ShowWindow(hwnd, SW_HIDE)` and returns 0.

### 6.5 Verify the lifecycle

- Close the main window. The window disappears, the tray icon remains, and the process stays alive.
- Wait at least 40 minutes in the tray.
- No Application Error 1000 record for the pid.
- The process is still alive, and the 32-bit module list still contains `crypt32.dll` if an HTTPS download was performed.

## 7. Crypt32 lifetime

### 7.1 Symptom

The process disappears without a dialog. Windows Error Reporting records:

```text
Faulting module name: CRYPT32.dll_unloaded
Exception code: 0xc0000005
Fault offset: 0x0005d220 (varies by crypt32 build)
```

The faulting instruction pointer is inside a module that has already been unmapped. The offset is not an export. The process uptime at death varies from 33 seconds to 47 minutes; the 20 to 25 minute window is a cluster, not a timer.

### 7.2 Mechanism

IDM uses crypt32 for certificate chain validation during HTTPS work:

1. `LoadLibraryA("Crypt32.dll")` or `LoadLibraryW(L"Crypt32.dll")` loads the module.
2. The handle is cached in a global.
3. `GetProcAddress("CertFindChainInStore")` resolves the function.
4. The pointer is cached in another global.
5. A worker thread calls the cached pointer.
6. A destructor or certificate path calls `FreeLibrary` or `LdrUnloadDll`.

If the unload lands while the worker is inside the module, the next instruction fetch goes into unmapped memory.

### 7.3 Find the chain

1. Search for the UTF-16 string `Crypt32.dll`.
2. Xref it to the `LoadLibraryW` or `LoadLibraryA` call. The return value is stored in a global.
3. Search for `CertFindChainInStore` or `CertGetCertificateChain`.
4. Xref it to `GetProcAddress`; the returned pointer is stored in a global.
5. Find indirect calls through that global.
6. Find `FreeLibrary` calls with the crypt32 handle. The handle may be loaded into a register or read from the global.
7. Use API Monitor or Frida to log `LoadLibrary`, `GetProcAddress`, `FreeLibrary`, and `LdrUnloadDll` with thread IDs and stacks. `LdrUnloadDll` may be called below `FreeLibrary` or from a certificate path that manages the module itself.
8. If the `Crypt32.dll` string is obfuscated, run an HTTPS download under API Monitor and log every `LoadLibrary` and `GetProcAddress` call. Crypt32 appears at the first certificate operation.

### 7.4 Fix 1: remove the free

NOP the `push` and the `FreeLibrary` call:

```text
50 FF 15 C0 84 6D 00  ->  90 90 90 90 90 90 90
```

That is 7 bytes: `push eax` plus the 6-byte indirect call. The stack is unchanged because both the push and the call are removed together.

If the sequence is different, count the bytes and remove the whole argument setup and call. Do not leave a stray `push` on the stack.

### 7.5 Fix 2: entry-point resident reference

If the module has multiple unload paths, hold one reference forever. Add a stub and make it the entry point; the stub calls `LoadLibraryA("Crypt32.dll")` or `LoadLibraryW(L"Crypt32.dll")`, never frees the reference, and then jumps to the original entry.

Generic stub shape:

```text
60                       pushad
68 <string_va>           push offset "Crypt32.dll"
FF 15 <LoadLibraryW>     call dword ptr [LoadLibraryW]
61                       popad
E9 <original_entry>      jmp original_entry
```

`pushad` and `popad` preserve the registers the original entry expects. The `LoadLibraryW` call uses the stdcall convention and cleans its own argument. The stub does not need to check the return value; if the load fails, the original code will handle it. Match the API to the import table: use `LoadLibraryW` with a UTF-16 string if the build imports the wide version, or `LoadLibraryA` with an ANSI string if it imports the ANSI version. Do not mix the two.

Place the stub in a code cave in the same section and set `AddressOfEntryPoint` to the stub's RVA. Leave the original entry intact, so the stub's final `jmp original_entry` lands on the original code, not on another jump. This is the 6.43 design.

If you cannot change `AddressOfEntryPoint`, overwrite the entry point with `E9 <rel32>` to the stub, copy the stolen entry bytes into the stub, and end with `jmp entry + stolen_length`. In that design, do not jump to `entry`, because `entry` now contains the jump to the stub and you would loop.

### 7.6 Verify the module lifetime

- Launch the patched image from its install path.
- Enumerate the 32-bit module list with Toolhelp32 (`TH32CS_SNAPMODULE32`), not a 64-bit PowerShell module read.
- Confirm `crypt32.dll` is present before any download.
- Perform an HTTPS download.
- Confirm `crypt32.dll` is still present after the download and after a `LdrUnloadDll` event.
- Close to the tray and sample at 60, 300, and 600 seconds, then at 40 minutes.
- Confirm no WER `CRYPT32.dll_unloaded` record for the pid.

A 32-bit Toolhelp32 loop, in C:

```c
HANDLE snap = CreateToolhelp32Snapshot(TH32CS_SNAPMODULE | TH32CS_SNAPMODULE32, pid);
MODULEENTRY32 me;
me.dwSize = sizeof(me);
BOOL found = FALSE;
for (BOOL ok = Module32First(snap, &me); ok; ok = Module32Next(snap, &me)) {
    if (_stricmp(me.szModule, "crypt32.dll") == 0) {
        found = TRUE;
        break;
    }
}
CloseHandle(snap);
```

Compile and run the loop as a 32-bit process. A 64-bit Toolhelp32 read uses the 64-bit structure layout and does not see the WOW64 modules correctly.

## 8. Helper process

`IDMGrHlp.exe` is a separate 32-bit MFC executable. `IDMan.exe` can launch it, and it can also be started directly. It shows the periodic fake-serial dialogs.

### 8.1 Find the helper dialogs

1. Open `IDMGrHlp.exe` in the disassembler.
2. Find the `MessageBoxA` or `MessageBoxW` imports and xref every call site.
3. Search for the fake-serial strings and xref them. The call sites that build those strings are the dialog sites.
4. In 6.43, the two call sites are at file offsets `0x52A1` and `0x52C8`.

If the helper uses a custom dialog resource instead of `MessageBox`, list its resources and apply the title-length cave from section 5.2 to the helper's dialog procedure.

### 8.2 Patch the helper

Each call site is a 6-byte indirect call:

```text
FF 15 <IAT MessageBoxA>  ->  31 C0 90 90 90 90
```

This skips the call and returns 0 in `EAX`. `MessageBoxA` is stdcall, so the call normally cleans its arguments. Removing the call also removes that cleanup. Inspect the instructions before the call:

- If no arguments are pushed immediately before the call, the six-byte patch is safe. This is the case at the 6.43 sites.
- If arguments are pushed immediately before the call, the patch leaves them on the stack. Add `add esp, n` after the patch, or replace the call with a `ret n` gadget that cleans the arguments and returns to the next instruction.

A safer generic alternative is to patch the function that builds the dialog, not the `MessageBox` call:

```text
31 C0 C3        xor eax, eax ; ret
```

Use this when the same function is called from several places.

### 8.3 Verify the helper

- Start `IDMGrHlp.exe` directly.
- It must exit with code 0.
- No window, no fake-serial text.
- Start IDM and let it run long enough for the helper to be launched. No helper dialog may appear.

If a new build merges the helper into `IDMan.exe`, apply the same patches to the `MessageBox` call sites in the main executable.

## 9. PE checksum

The PE optional header checksum is at:

```text
file offset = e_lfanew + 4 + 20 + 0x40
```

For a standard PE32 header, that is file offset `0x150`. Compute it from `e_lfanew`, do not hardcode `0x150` in a tool that must work on other builds.

The checksum algorithm:

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

Recompute the checksum after every code patch, including the entry stub, the dialog cave, and the helper patches. Write the result last. The Windows loader does not normally verify the checksum for an executable, but IDM's own integrity check may compare it. A correct checksum removes one variable from the crash and dialog investigations.

The generic patcher in section 10 recomputes the checksum automatically. If you patch by hand, run the function above and write the 4-byte little-endian result at the checksum field.

## 10. Generic patcher and manifest

The patcher is version-agnostic. It reads a JSON manifest, applies offset or pattern patches, verifies the original bytes, refuses overlaps, and recomputes the PE checksum.

### 10.1 Manifest schema

```json
{
  "patches": [
    {
      "name": "serial_validator",
      "offset": "0x5A830",
      "original": "55 8B EC",
      "patch": "B0 01 C3"
    },
    {
      "name": "crypt32_free",
      "pattern": "50 FF 15 ?? ?? ?? ??",
      "original": "50 FF 15 C0 84 6D 00",
      "patch": "90 90 90 90 90 90 90"
    }
  ]
}
```

Rules:

- `offset` is a file offset, not a VA or RVA. Accepts `0x` hex or decimal.
- `original` is optional for offset patches, but always include it. The patcher fails if the bytes do not match.
- `pattern` is a byte pattern with `??` wildcards. It must match exactly once unless `allow_multiple` is true.
- `patch` is the exact replacement bytes. The patcher does not pad; include every byte you want to write.
- Patches must not overlap. The patcher fails on overlap, which catches a cave patch that accidentally covers a code site.
- `expected_sha256` is optional. Use it for a local regression check, not as a hardcoded build identity.

### 10.2 The patcher

```python
#!/usr/bin/env python3
"""Apply a JSON patch manifest to a PE file and recompute the PE checksum."""

import argparse
import hashlib
import json
import struct
import sys


def hex_bytes(text):
    return bytes.fromhex(text.replace(" ", ""))


def parse_pattern(text):
    data = []
    mask = []
    for token in text.split():
        if token in ("??", "?"):
            data.append(0)
            mask.append(False)
        else:
            data.append(int(token, 16))
            mask.append(True)
    return bytes(data), mask


def find_pattern(data, pattern, mask):
    hits = []
    n = len(pattern)
    for i in range(0, len(data) - n + 1):
        for j in range(n):
            if mask[j] and data[i + j] != pattern[j]:
                break
        else:
            hits.append(i)
    return hits


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


def checksum_field(data):
    e_lfanew = struct.unpack("<I", data[0x3C:0x40])[0]
    return e_lfanew + 4 + 20 + 0x40


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("manifest")
    ap.add_argument("input")
    ap.add_argument("output")
    ap.add_argument("--in-place", action="store_true")
    args = ap.parse_args()

    if args.output == args.input and not args.in_place:
        print("refusing to overwrite the input without --in-place")
        return 2

    data = bytearray(open(args.input, "rb").read())
    manifest = json.load(open(args.manifest))
    patches = manifest.get("patches", [])

    applied = []
    occupied = []
    for spec in patches:
        name = spec.get("name", "patch")
        patch = hex_bytes(spec["patch"])
        if "offset" in spec:
            offset = int(str(spec["offset"]), 0)
            if "original" in spec:
                original = hex_bytes(spec["original"])
                got = bytes(data[offset:offset + len(original)])
                if got != original:
                    print("%s: original mismatch at 0x%X" % (name, offset))
                    print("  expected %s" % original.hex(" "))
                    print("  found    %s" % got.hex(" "))
                    return 1
        elif "pattern" in spec:
            pattern, mask = parse_pattern(spec["pattern"])
            hits = find_pattern(data, pattern, mask)
            if len(hits) != 1 and not spec.get("allow_multiple"):
                print("%s: pattern matched %d times, expected 1" % (name, len(hits)))
                return 1
            if not hits:
                print("%s: pattern not found" % name)
                return 1
            offset = hits[0]
            if "original" in spec:
                original = hex_bytes(spec["original"])
                got = bytes(data[offset:offset + len(original)])
                if got != original:
                    print("%s: matched bytes do not equal original" % name)
                    return 1
        else:
            print("%s: needs offset or pattern" % name)
            return 1

        end = offset + len(patch)
        if end > len(data):
            print("%s: patch runs past end of file" % name)
            return 1
        for a, b in occupied:
            if offset < b and a < end:
                print("%s: overlaps another patch at 0x%X..0x%X" % (name, a, b))
                return 1
        data[offset:end] = patch
        occupied.append((offset, end))
        applied.append((name, offset, len(patch)))

    chk = checksum_field(data)
    value = pe_checksum(bytes(data), chk)
    data[chk:chk + 4] = struct.pack("<I", value)

    open(args.output, "wb").write(data)
    print("%-32s %-10s %s" % ("patch", "offset", "bytes"))
    for name, offset, length in applied:
        print("%-32s 0x%08X %d" % (name, offset, length))
    print("checksum 0x%08X at file 0x%X" % (value, chk))
    print("input  sha256 %s" % hashlib.sha256(open(args.input, "rb").read()).hexdigest().upper())
    print("output sha256 %s" % hashlib.sha256(data).hexdigest().upper())
    expected = manifest.get("expected_sha256")
    if expected and expected.upper() != hashlib.sha256(data).hexdigest().upper():
        print("FAIL expected SHA256 %s" % expected.upper())
        return 1
    print("PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
```

### 10.3 Usage

```text
python patcher.py manifest.json IDMan.pristine.exe IDMan.patched.exe
```

The patcher prints every applied patch, the checksum, and the local input and output hashes. It does not modify the input unless you pass `--in-place`.

### 10.4 Offset patches and pattern patches

Use offset patches when you have identified the exact build and verified the original bytes. Use pattern patches when the build may have moved, or when you want the manifest to survive a minor update.

Pattern design:

- Include at least 8 to 16 bytes around the patch site.
- Use `??` for relative offsets, absolute addresses, and register numbers that may change.
- Prefer bytes from the instruction encoding that are stable across builds, not string or data bytes.
- Test the pattern against the pristine file before patching. It must match once.
- If a pattern matches multiple times, add context bytes until it is unique. Do not use `allow_multiple` for a code patch unless every match should be patched.

Example pattern for the 6.43 crypt32 free:

```text
50 FF 15 C0 84 6D 00
```

The `C0 84 6D 00` is the IAT slot for `FreeLibrary`, which changes between builds. A version-agnostic pattern would wildcard it:

```text
50 FF 15 ?? ?? ?? ??
```

But that pattern is not unique by itself. Add the surrounding function bytes or use the cached handle load as context.

### 10.5 Generate a manifest from a diff

The reliable way to build a manifest for a known version:

1. Keep a pristine copy.
2. Patch one site at a time in a test copy, or build the full patched file.
3. Diff the pristine and patched files.
4. Group contiguous byte runs into patches.
5. Exclude the checksum field at `0x150` or the computed checksum offset.
6. Merge cave and entry-stub writes into one patch per cave.
7. Add `original` bytes from the pristine file.
8. Reapply the manifest to the pristine file with the patcher and compare the result to your hand-built file.

A simple diff:

```python
a = open("IDMan.pristine.exe", "rb").read()
b = open("IDMan.patched.exe", "rb").read()
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

The diff is a starting point, not a finished manifest. Merge adjacent runs, split a run if it mixes a code patch and a data patch, and add context for pattern matching.

### 10.6 Test the manifest

Always test on a copy:

1. Apply the manifest to the pristine file.
2. Compare the output to your hand-built patched file. They must be identical.
3. Launch the output from a test directory, with `ExePath` set to that exact path.
4. Run the verification matrix in section 13.
5. Only then write the patched file to the install directory.

If the output differs, the manifest is missing a patch, has an extra patch, or applied a patch at the wrong offset. Do not debug the live install; debug the manifest on the copy.

### 10.7 Install and launch

1. Close `IDMan.exe` and `IDMGrHlp.exe`. Confirm no process remains.
2. Back up the installed `IDMan.exe` and `IDMGrHlp.exe` outside the install directory.
3. Write the patched `IDMan.exe` to the install directory with elevation.
4. Write the patched `IDMGrHlp.exe` if you patched the helper.
5. Set `HKCU\Software\DownloadManager\ExePath` to the exact install path, for example `C:\Program Files (x86)\Internet Download Manager\IDMan.exe`.
6. Launch from that exact path.
7. If the process exits in about 0.12 seconds with no window, the `ExePath` value does not match the launched image. Fix it before investigating anything else.
8. Run the verification matrix in section 13.

The `ExePath` check is a gate, not a license check. It compares the launched image path with the registry value. A mismatch produces a silent exit, which looks like a failed patch but is usually just the wrong path.

## 11. Version drift guide

Every layer has stable anchors and unstable offsets. The stable anchors are strings, API imports, registry names, serial format constants, dialog titles, and status codes. The unstable parts are addresses, register allocation, function order, and compiler-generated prologues.

| Layer | Stable anchors | 6.43 b18 example | How to re-find in a new build |
|---|---|---|---|
| Version and entry | File version, `idmvers`, PE header | `v6.43b18` | File properties, `pefile`, About dialog |
| Serial validators | `Serial`, `FName`, `LName`, `Email`, length 23, hyphens at 5, 11, 17 | `0x5A4B0`, `0x5A830` | Xref the registry strings and the length constants |
| Status dispatcher | Small status codes, jump table, UI strings | `0x450630`, switch `0x452535`, table `0x4534BC` | Find the caller of the validators and follow the switch |
| Registration dialog | Title `Internet Download Manager Registration`, `DialogBoxParamW` | proc `0x651762` | Resource list, title xref, `DialogBoxParamW` call |
| Warning | `fake Serial Number`, `counterfeit` | `0x474760`, call sites `0x93B5F`, `0x74E84` | Xref the string, patch the function or call |
| Licensed-to | `This product is licensed to` | call `0x489FA6` | Xref the string and the formatter |
| Buy page | `buy`, `buy2.html`, `buy_idm2.html`, `ShellExecute` | `0x7C1A0`, `0x7EA43` | Xref the URL strings and `ShellExecute` |
| Update check | `LastCheckQU`, HTTP, timer | `0x55DD0` | Xref the registry value |
| Timers | `SetTimer`, intervals `0x124F80`, `0x927C0`, `0x2BF20` | many | Enumerate `SetTimer` calls, inspect `WM_TIMER` cases |
| Quit | `PostQuitMessage` IAT | four sites | Xref the IAT slot |
| Exit | `ExitProcess` IAT | five sites | Xref the IAT slot |
| Tray | `WM_CLOSE`, `ShowWindow` | `0x88C15`, cave `0x896F4` | Window proc `WM_CLOSE` case |
| Crypt32 load | `Crypt32.dll`, `LoadLibrary`, `GetProcAddress` | `0x5EF4D2`, `0x5EF517` | Xref the string and the cert API names |
| Crypt32 free | Cached handle, `FreeLibrary`, `LdrUnloadDll` | `0x4484B2` | Follow the handle global and API Monitor |
| Helper | `IDMGrHlp.exe`, `MessageBoxA` | `0x52A1`, `0x52C8` | Xref the helper's MessageBox calls |
| Checksum | PE optional header | `0x150` | `e_lfanew + 4 + 20 + 0x40` |

### 11.1 What usually changes

- Addresses and offsets. Every build shifts code and data.
- Function order and inlining. A validator may be inlined into its caller.
- Register allocation. A cached handle may move from one register to another.
- Dialog resource IDs and control order.
- String addresses and occasional wording changes.
- Timer IDs and intervals.
- The compiler's prologue and epilogue.

### 11.2 If the binary is packed or protected

Check the section names, entropy, imports, and entry point. A packed binary has few imports, a writable and executable section, and a stub at the entry point. Unpack it before analysis:

1. Run it in a VM under a debugger.
2. Break after the unpacking stub, when the original entry point is reached.
3. Dump the process image with a PE dump tool.
4. Rebuild the import table if needed.
5. Verify the dumped image runs.

IDM's standard builds are not packed, but a future build or a third-party repack may change that.

### 11.3 If the build is 64-bit

A 64-bit build changes the calling convention, the PE format (PE32+), the register set, and the module list. The same layer model applies, but the byte patterns and the cave code do not. Treat a 64-bit build as a new target:

- Use a 64-bit debugger and a 64-bit disassembler.
- The first four arguments are in `RCX`, `RDX`, `R8`, `R9`; stack arguments start at `[rsp+0x28]`.
- The dialog procedure arguments are in registers, not at `[ebp+0xC]`.
- The entry stub must preserve the 64-bit calling convention and use `LoadLibraryW` from the 64-bit process.
- The module list is native, so a 64-bit enumeration is correct.

### 11.4 If the UI is rewritten

The dialog procedure may have a different title, different controls, or a new framework. Do not rely on the exact title length. Instead:

- Find the dialog by its control text (`Serial`, `First Name`, `Last Name`, `Email`) or by the resource ID used at the `DialogBoxParamW` call.
- In the cave, use `GetDlgItem` to check for a known control ID, or `GetWindowTextW` to compare the full title.
- If the dialog is created with `CreateDialogParamW` and shown with `ShowWindow`, patch the creation call or the `ShowWindow` call.

### 11.5 If crypt32 is loaded differently

The load may be delayed until the first HTTPS download, or it may use `LoadLibraryExW` with flags. Use API Monitor or Frida to log:

- `LoadLibraryW`, `LoadLibraryExW`, `GetProcAddress`, `FreeLibrary`, `LdrUnloadDll`.
- The return values and the globals where they are stored.
- The thread ID and stack at each unload.

If the module is loaded by a delay-load helper, patch the delay-load call or the free, not the visible `LoadLibrary` site.

### 11.6 If the helper is merged

If `IDMGrHlp.exe` disappears and the dialogs move into `IDMan.exe`, search the main executable for the same fake-serial strings and `MessageBox` calls. Patch those call sites with the same six-byte skip.

### 11.7 Validating a new build

1. Record the version and baseline behavior.
2. Fill the anchor table in section 3.4.
3. Patch one layer at a time on a copy.
4. Run the layer's verification.
5. Build a manifest and apply it to a fresh pristine copy.
6. Compare the manifest output to your hand-built file.
7. Run the full verification matrix in section 13.
8. Only then install.

## 12. Worked example: 6.43 build 18

The offsets below are a reference map for one exact build. They are not universal. On any other build, use section 11 to re-find each site.

### 12.1 License and UI

| Offset | Original | Patch | Purpose |
|---:|---|---|---|
| `0x4FFC4` | `74 15` | `EB 15` | Force the online registration branch to success |
| `0x5A4B0` | `55 8B EC` | `B0 01 C3` | Name validator returns true |
| `0x5A830` | `55 8B EC` | `B0 01 C3` | Serial validator returns true |
| `0x50C1C` | `B8 03 00 00 00` | `B8 00 00 00 00` | Counterfeit status becomes registered |
| `0x50083` | `B8 06 00 00 00` | `31 C0 90 90 90` | Trial-expired status becomes registered |
| `0x93B5F` | `E8 FC FF FD FF` | `31 C0 90 90 90` | Skip the first fake-serial warning |
| `0x74E84` | `E8 D7 EC FF FF` | `31 C0 90 90 90` | Skip the second fake-serial warning |
| `0x55DD0` | `55 8B EC` | `33 C0 C3` | Disable the automatic update check |
| `0x7C1A0` | `55` | `C3` | Disable the first buy-page URL builder |
| `0x7EA43` | `E8 B8 7C 03 00` | `31 C0 90 90 90` | Skip the timer buy-page opener |
| `0x863E9` | `0F 84 78 01 00 00` | `E9 79 01 00 00 90` | Force the timer's registered path |

### 12.2 Tray and exit

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
| `0x76665` | `68 20 BF 02 00` | `68 FF FF FF 7F` | Timer 21 arm A becomes INFINITE |
| `0x8DA5C` | `68 20 BF 02 00` | `68 FF FF FF 7F` | Timer 21 arm B becomes INFINITE |
| `0x14E902` | `FF 15 5C 86 6D 00` | `58 90 90 90 90 90` | Tray `WM_DESTROY`: no `WM_QUIT` |
| `0xB7E27` | `FF 15 5C 86 6D 00` | `58 90 90 90 90 90` | Second `PostQuitMessage` site |
| `0xE21BE` | `FF 15 5C 86 6D 00` | `58 90 90 90 90 90` | Third `PostQuitMessage` site |
| `0xE2647` | `FF 15 5C 86 6D 00` | `58 90 90 90 90 90` | Fourth `PostQuitMessage` site |
| `0x101DA` | `CC` | `C3` | `int3` after site 18 becomes `ret` |
| `0x25F5A0` | `FF 25 5C 86 6D 00` | `C3 90 90 90 90 90` | Tail-jump thunk to `PostQuitMessage` becomes `ret` |

The tray cave at `0x896F4`:

```text
8B 75 08 83 FE 10 74 0A 8B C6 83 E8 01 E9 17 F5 FF FF
6A 00 FF 77 20 FF 15 DC 87 6D 00 E9 34 F5 FF FF
```

It checks for `WM_CLOSE`, calls `ShowWindow(hwnd, SW_HIDE)`, and returns 0 through the normal function epilogue.

### 12.3 Crypt32 lifetime

| Offset | Original | Patch | Purpose |
|---:|---|---|---|
| `0x478B1` | `50 FF 15 C0 84 6D 00` | `90 90 90 90 90 90 90` | Drop the `push` and `FreeLibrary` of the cached crypt32 handle |
| `0x2D6A4C` | zero padding | 35-byte entry stub | Load crypt32 at the entry point and hold a reference |
| `0x120` | original entry RVA | `4C 76 2D 00` | Point `AddressOfEntryPoint` at RVA `0x2D764C` |

Entry stub, 35 bytes at file `0x2D6A4C`:

```text
E8 00 00 00 00 58 2D 51 76 2D 00 89 C3 60 8D 83 88 F8 30 00
50 8B 93 EC 83 2D 00 FF D2 61 E9 7D D7 FA FF
```

The stub calls `LoadLibraryW(L"Crypt32.dll")` through the cached IAT pointer, preserves registers with `pushad` and `popad`, and jumps back to the original entry. The string at RVA `0x30F888` is UTF-16, and the IAT slot at RVA `0x2D83EC` is `LoadLibraryW`.

### 12.4 Inside dialog suppression

| Offset | Original | Patch | Purpose |
|---:|---|---|---|
| `0x250B62` | `8B FF 55 8B EC` | `E9 19 5F 08 00` | Dialog procedure jumps to the cave |
| `0x2D6A80` | zero padding | 79-byte cave | Close the title length 38 registration dialog |
| `0x73B60` | `6A FF 68 88 78 6A` | `31 C0 C3 88 78 6A` | Warning function returns 0 |
| `0x893A6` | `E8 F5 24 06 00` | `31 C0 90 90 90` | Skip the licensed-to confirmation |
| `0xA7F86` | `FF 15 68 86 6D 00` | `31 C0 90 90 90 90` | Skip the custom dialog wrapper |

Dialog cave, 79 bytes at file `0x2D6A80`:

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

The cave uses the IAT slots at RVA `0x2D87E4` (`GetWindowTextLengthW`) and `0x2D87E8` (`PostMessageA`).

### 12.5 Helper

| Offset | Original | Patch | Purpose |
|---:|---|---|---|
| `0x52A1` | `FF 15 BC 34 44 00` | `31 C0 90 90 90 90` | Suppress the short fake-serial dialog |
| `0x52C8` | `FF 15 BC 34 44 00` | `31 C0 90 90 90 90` | Suppress the long fake-serial dialog |

### 12.6 Checksum

Recompute the PE checksum at file `0x150` after all code patches. The generic patcher in section 10 does this automatically.

### 12.7 Patch order

The table is a patch map, not a ready-made manifest. Create one manifest entry per row. If a row combines adjacent diff runs, either write the full original and patch bytes for the row, or split it at the changed bytes. Verify each original byte before applying.

1. Apply the code patches to the copy.
2. Apply the entry stub and the dialog cave.
3. Recompute the checksum.
4. Write the file to the install directory with elevation.
5. Set `ExePath` to the exact install path.
6. Launch and run the verification matrix.

## 13. Verification matrix and failure modes

### 13.1 Verification matrix

| Check | Pass condition |
|---|---|
| Registry | `idmvers` is `Full`, `ExePath` names the launched image |
| About | Registered state, no trial counter |
| Registration menu | No registration window, no warning, no licensed-to |
| Download | Only the normal `Download File Info` and `Download complete` windows |
| Buy page | No `buy2.html` or `buy_idm2.html` process |
| Update | `LastCheckQU` does not change during a normal launch |
| Tray | Close hides the window, the tray icon remains, the process stays alive |
| Crypt32 | 32-bit module list contains `crypt32.dll` before and after an HTTPS download |
| Soak | Process alive after 40 minutes in the tray |
| WER | No Application Error 1000 with `CRYPT32.dll_unloaded` for the pid |
| Helper | `IDMGrHlp.exe` exits 0 and shows no window |
| Checksum | Stored PE checksum equals the computed value |
| Manifest | Applying the manifest to a fresh pristine copy produces the same file |

### 13.2 Failure modes

| Symptom | Cause | Fix |
|---|---|---|
| Process exits in about 0.12 seconds with no window | `ExePath` does not match the launched image | Set `ExePath` to the exact launched path |
| About shows `Trial` with the full build | The status stub forces 0, or the serial is blacklisted | Restore the status function, suppress the UI, use a random serial |
| Registration window appears at startup, then the 15-day warning and exit | The status machine returns 6 (trial expired); only the counterfeit return was patched | Patch the `mov eax, 6` immediate (section 4.4), keep the UI suppression patches |
| Registration window still appears | The dialog procedure cave is missing or the title length is wrong | Recheck the proc jump, the cave, and the title length |
| Fake-serial warning still appears | The warning function or call site is unpatched | Patch the function or both call sites |
| Licensed-to dialog still appears | The licensed-to call is unpatched | Patch the call or the formatter |
| Buy page opens | The URL builder or `ShellExecute` call is unpatched | Patch the builder or the call |
| Update check runs | The check function or timer is unpatched | Patch the shared check function |
| Crash after an HTTPS download | The crypt32 free is still present, or the entry stub is missing | Recheck section 7 |
| WER `CRYPT32.dll_unloaded` | `crypt32.dll` is not resident | Apply the free removal or the entry stub |
| Module list says crypt32 is absent but the process works | A 64-bit module read on a 32-bit process | Use a 32-bit Toolhelp32 enumerator |
| Soak ends when a second IDMan starts | The single-instance mutex and `ExePath` gate | Kill every IDMan before a soak |
| Installed file is write protected | Program Files ACL | Use an elevated process |
| Patcher reports overlap | Two patches cover the same bytes | Split or reorder the manifest |
| Crash after a call patch | Stack cleanup is wrong | Check cdecl vs stdcall, use a `ret n` gadget or `pop` |
| Helper dialog appears | The helper `MessageBox` calls are unpatched | Patch both helper sites |

## 14. Operational notes

- Keep a pristine copy of every build you work on.
- Keep the patch manifest next to the build. The manifest is the reproducible artifact.
- Record the local input and output hashes in your notes. Hashes are for your own regression checks, not a substitute for a manifest.
- Work in a VM snapshot. A bad patch can corrupt the registry or the install.
- Re-run the discovery workflow after every update. An update replaces `IDMan.exe` and `IDMGrHlp.exe`.
- If the app updates itself, the installed patched file is replaced. Reapply the manifest and recompute the checksum.
- Do not distribute patched binaries. Distribute the method and the manifest if you share the work.

## Appendix A: API and byte-pattern index

| Target | Pattern or API | Notes |
|---|---|---|
| Function prologue | `55 8B EC` or `8B FF 55 8B EC` | MSVC x86 |
| Return false | `31 C0 C3` | `xor eax,eax; ret` |
| Return true (AL) | `B0 01 C3` | `mov al,1; ret` |
| Return true (EAX) | `31 C0 FF C0 C3` | `xor eax,eax; inc eax; ret` |
| Skip a call, return 0 | `31 C0 90 90 90 90` | 6-byte indirect call |
| Remove a push and call | `90` x 7 | 1-byte push plus 6-byte call |
| `PostQuitMessage` call | `FF 15 <IAT>` | Preceded by `push 0` |
| `PostQuitMessage` jump | `FF 25 <IAT>` | Patch to `C3 90 90 90 90 90` |
| `ExitProcess` call | `FF 15 <IAT>` | Patch to a `ret` gadget |
| `LoadLibraryW` call | `FF 15 <IAT>` | Stdcall, one argument |
| `GetProcAddress` call | `FF 15 <IAT>` | Stdcall, two arguments |
| `FreeLibrary` call | `FF 15 <IAT>` | Stdcall, one argument |
| `DialogBoxParamW` call | `FF 15 <IAT>` or `E8` | Proc pointer is an argument |
| `MessageBoxW` call | `FF 15 <IAT>` | 6-byte indirect call |
| `SetTimer` call | `FF 15 <IAT>` | Interval is a `push` immediate |
| 20 minute timer | `68 80 4F 12 00` | 1,200,000 ms |
| 10 minute timer | `68 C0 27 09 00` | 600,000 ms |
| 3 minute timer | `68 20 BF 02 00` | 180,000 ms |
| 32 second timer | `68 00 7D 00 00` | 32,000 ms |
| 12 second timer | `68 E0 2E 00 00` | 12,000 ms |
| 10 second timer | `68 10 27 00 00` | 10,000 ms |
| Serial length | `83 F8 17` or `3D 17 00 00 00` | 23 decimal |
| Hyphen check | `80 78 05 2D` | `cmp byte ptr [eax+5], '-'` |

## Appendix B: discovery worksheet

Copy this JSON and fill it before patching. Every empty field is a discovery task.

```json
{
  "target": {
    "file": "IDMan.exe",
    "version": "",
    "architecture": "PE32",
    "entry_point": "",
    "notes": ""
  },
  "anchors": {
    "serial_validator_1": {"offset": "", "pattern": "", "confidence": ""},
    "serial_validator_2": {"offset": "", "pattern": "", "confidence": ""},
    "status_function": {"offset": "", "pattern": "", "confidence": ""},
    "status_switch": {"offset": "", "pattern": "", "confidence": ""},
    "registration_proc": {"offset": "", "pattern": "", "confidence": ""},
    "warning_function": {"offset": "", "pattern": "", "confidence": ""},
    "licensed_to_call": {"offset": "", "pattern": "", "confidence": ""},
    "buy_page_call": {"offset": "", "pattern": "", "confidence": ""},
    "update_check": {"offset": "", "pattern": "", "confidence": ""},
    "post_quit_sites": [],
    "exit_process_sites": [],
    "tray_close": {"offset": "", "pattern": "", "confidence": ""},
    "crypt32_load": {"offset": "", "pattern": "", "confidence": ""},
    "crypt32_free": {"offset": "", "pattern": "", "confidence": ""},
    "helper_dialogs": []
  },
  "patches": []
}
```

The worksheet is the handoff artifact. Another agent should be able to read it, apply the manifest, and reproduce the build without repeating the discovery.
