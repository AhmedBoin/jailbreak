# Adobe Acrobat 25.1: Pro entitlement in two writes

Target: Adobe Acrobat 25.1, native x64. Worked example: `Acrobat.exe` 25.1.21208.0,
`Acrobat.dll` 25.1.21208.7, NGL client 25.1.21208.7. Every address below belongs to
that exact build. Treat them as evidence for the model, not as constants for the next
build.

This runbook is written to be executed. It assumes an agent with a debugger, a hex
editor, and the ability to read a process at runtime. It does not assume source, a
keygen, or a network account.

The claim in the title is literal. The patch is two stores. The only work is finding
the two decisions, and phase 4 gives the loop that finds them in minutes on a build
that has never been seen.

---

## 0. Contract

### 0.1 What "cracked" means here

The application must satisfy all of the following on a cold start with no account and
no network:

| Property | Evidence |
|---|---|
| Product mode is Professional | `app.viewerType` returns `Exchange-Pro` |
| Entitlement is 300 | NGL log says `Entitlement is 300` and names Acrobat Professional |
| A Pro-only API executes | `addWatermarkFromText` succeeds on a test document |
| No trial surface | no `adobe_licensing_wf_acro.exe` process, no `EmbeddedWB` window |
| UI stays alive | window answers `WM_NULL` within one second for 60 seconds |
| Patch is on disk | both byte ranges read back from `Acrobat.dll` |

The registry alone is never evidence. The NGL log alone is never evidence. A screenshot
of a title bar is never evidence. The matrix above is the gate.

### 0.2 The one rule

**Patch the decision the process makes, not the string it prints.** Acrobat's own log
will happily print `Entitlement is Acrobat Professional` from a formatter that has no
effect on behavior. The test is a Pro-only API and the absence of the workflow host,
not a sentence in a log.

### 0.3 Files in scope

```text
C:\Program Files\Adobe\Acrobat DC\Acrobat\
  Acrobat.exe                       6,399,960 bytes, the UI process
  Acrobat.dll                      79,011,288 bytes, the licensing consumer
  NGL\cefWorkflow\
    adobe_licensing_wf_acro.exe     3,448,280 bytes, the CEF trial/sign-in host
    adobe_licensing_wf_helper_acro.exe
```

`Acrobat.exe` has no static import of `Acrobat.dll`. Its import table is KERNEL32,
USER32, ADVAPI32, SHLWAPI, a WinRT stub, and WINHTTP. The DLL is loaded by name at
runtime, relative to the executable's directory. That is why a copy tree works, and why
the DLL is the right carrier for a file patch.

---

## 1. The model

Acrobat 25.1 has two independent decisions. Most failed attempts patch one and then
blame the other.

| Decision | Owner | Input | Output |
|---|---|---|---|
| Entitlement level | `Acrobat.dll` function at `0x6DA6C4` | cached NGL profile and HKCU state | integer level: 1 Reader, 100 Standard, 300 Professional |
| Workflow required | `Acrobat.dll` function `InitializeWorkflows` at `0x6E248C` | NGL status, locale, config | starts the CEF host that paints the trial sheet |

The server-signed NGL profile is not the lever. It is an AES blob with a keyed MAC,
fetched from Adobe and verified locally; it says `LICENSE_TYPE_NONE`,
`FIAcrobatStd:0`, `FIAcrobatPro:0`, no serial. Forging it is a cryptographic dead end.
But the client still has to convert that profile into a local integer and decide
whether to start a workflow. Those two local decisions are patchable.

The level gate lives at `0x7DBE80` to `0x7DC056`: it reads the level, compares against
`0x64`, and falls back to Reader below it. Set the level to 300 and every gate that
uses the same record passes.

The workflow decision is separate. Even with level 300, a 401 profile status still
causes `InitializeWorkflows` to spawn the CEF host. The host performs a handshake; if
it never completes, the Acrobat UI thread blocks. That is why killing the host after it
starts, or replacing it with a process that sleeps, produces a frozen window rather
than a clean crack. The only clean move is to never call `InitializeWorkflows`.

---

## 2. Reference build

```text
Acrobat.dll size            79,011,288
pristine SHA256             F58581CBC18B4284B12E42399B4E0C2C6A18FBFB26824AA7E3B0917D5E7621FE
patched SHA256              4FC9D1DC55EAE69637D3E13E8E55F04CABCA58C0747E8983DCF91A6B857BB3BE

Section .text
  VirtualAddress            0x1000
  VirtualSize               0x326AC7A
  PointerToRawData          0x400
  SizeOfRawData             0x326AE00

File offset                0x400 + (RVA - 0x1000)
```

The image is not packed. Strings used by the licensing consumer are plain ASCII in
`.rdata`, and the code is ordinary MSVC x64 with `.pdata` function records. That makes
runtime evidence and function boundaries cheap to obtain.

---

## 3. The two patches

### 3.1 Entitlement level

| Field | Value |
|---|---|
| RVA | `0x6DA6D1` |
| File offset | `0x6D9AD1` |
| Function | `0x6DA6C4` to `0x6DA7A5` |
| Offset in function | `+0xD` |
| Original | `BB 01 00 00 00` (`mov ebx, 1`) |
| Patch | `BB 2C 01 00 00` (`mov ebx, 0x12C`, 300) |
| Bytes after | `E8 21 35 B4 FF` (call), `48 8B C8` (mov rcx, rax), `E8 ED 89 ...` |

The function reads the license state and returns the level. The literal 1 is the
fallback that produces Reader. Rewriting it to 300 makes every consumer of the same
record, including the gate at `0x7DBE80`, see Professional. The application writes 300
back to `HKCU\SOFTWARE\Adobe\Adobe Acrobat\DC\AVEntitlement\iEntitlementLevel`, and
the value survives restarts because the patched mapper keeps producing it.

`Acrobat.dll+0x6DA9BF` is the log formatter that chooses between
`Entitlement is Reader/Residue.` and `Entitlement is Acrobat Professional.` It sits
later in the same region and is not the decision. Patching it changes a sentence.

### 3.2 Workflow initializer

| Field | Value |
|---|---|
| RVA | `0x6E248C` |
| File offset | `0x6E188C` |
| Function | `0x6E248C` to `0x6E2DB5` |
| Original | `48 8B C4` (`mov rax, rsp`) |
| Patch | `33 C0 C3` (`xor eax, eax; ret`) |
| Full original prologue | `48 8B C4 44 88 40 18 53 56 57 41 54 41 55 41 56` |

`InitializeWorkflows` is called from the NGL initialization function at `0x6BAC1C`
(`0x6BAC1C` to `0x6BB3BE`). The call site is `0x6BB0EB`:

```text
0x6BB0E7  49 8B 4E 08        mov rcx, [r14+8]
0x6BB0EB  E8 9C 73 02 00     call 0x6E248C
0x6BB0F0  E8 5B B6 B7 FF     call 0x60236750
0x6BB0F5  66 85 C0           test ax, ax
0x6BB0F8  0F 85 BE 01 00 00  jne error path
```

Returning 0 from the function leaves `test ax, ax` with zero, which is the "no error"
branch, and the code continues without a host. No process is created, no pipe
handshake is awaited, and no window is painted.

The spawn itself is elsewhere, for reference only: `Acrobat.dll+0x8F3708` is the
`CreateProcessW` call inside the large function `0x8F1DB0` to `0x8F5BFE`. It is passed
the literal `NGL\cefWorkflow\adobe_licensing_wf_acro.exe` from `.rdata` at
`0x39883C8` and the parent PID as the command line. Patching the call site instead of
the initializer leaves the process-creation structures half-built and is not
recommended. Patching `InitializeWorkflows` is one instruction and removes the entire
subtree.

---

## 4. Why the obvious routes fail

Every row below was measured on this build. They are listed so an agent does not spend
a session rediscovering them.

| Route | Observed result | Why |
|---|---|---|
| Set `sAppEntitlementStatus` to `PAID` | reverts to `NOVALUE` during startup | the client re-derives it from the sealed blob and rewrites the key |
| Set `iEntitlementLevel` to 2 or 300 in the registry | reverts to 1 on a pristine DLL | the mapper computes the value before reading the cache |
| Patch the three jumps `0x7DBFBC`, `0x7DBFD6`, `0x7DC0CF` | level record changes, host still spawns | those sites belong to the feature gate, not the workflow decision |
| Forge the NGL profile blob | impossible | AES ciphertext plus keyed MAC, key inside signed IMSLib |
| Kill `adobe_licensing_wf_acro.exe` after it starts | trial sheet gone, UI thread hung | the initializer waits for a handshake that a dead host cannot complete |
| Replace the host with a sleeping stub | same hang | process exists, handshake never happens |
| Replace the host with an instant-exit stub | same hang | exit is not a handshake either |
| Patch only the level mapper | no trial sheet change, host still spawns | the workflow decision is independent of the level |
| Copy the tree to a writable directory | copy loads, but the installed DLL is also loaded; the decision may not run | the app resolves its install from registration, not only from its own path |
| Patch `acrotray.exe` or `acrodistdll.dll` | no effect on the Acrobat trial sheet | they carry their own copies of the NGL code, not the UI path |

The last two rows are the reason the installed DLL is the correct target: patch
`Acrobat.dll` in place, in the real install directory.

---

## 5. Locate the sites on a new build

Do not search for byte patterns in a 79 MB file and hope. Use the runtime to tell you
which function matters, then read that function statically. The loop has four
artifacts: the log, the backtrace, the function boundary, and the bytes.

### 5.1 Read the verdict first

Launch Acrobat on any PDF and read `%TEMP%\acroNGLLog.txt`. A cold start that needs a
patch ends with this sequence:

```text
CheckingLicenseValidity from cache profile...
== printProfileData Profile ErrorCode : [401]
401 WORKFLOW_REQUIRED : PROFILE_EXPIRED : PROFILE_UNAVAILABLE : ...
NGL Fulfillment Data
  FIAcrobatStd:0  FIAcrobatPro:0  FIAcrobatGenAI:0  FIAcrobatStudio:0
Entitlement is 1
ACROBAT LICENSE CHANGE NOTIFICATION : Entitlement is Reader/Residue.
InitializeWorkflows with locale : en_US launchLocale : en_US
```

`401` and `WORKFLOW_REQUIRED` are the profile verdict. `Entitlement is 1` is the
mapper. `InitializeWorkflows` is the decision that follows. If `Entitlement is 300`
already appears, the level patch is present and only the workflow half is missing.

The matching client log is `%TEMP%\NGL\NGLClient_AcrobatDC<version>.log`. It records
`InitializeWorkflows: invoked` at the same moment.

### 5.2 Get the backtrace of the log write

Hook the file write that emits the `CheckingLicenseValidity` batch, either with a
debugger breakpoint on `WriteFile` filtered by the log handle or with a runtime hook
that inspects the buffer. The call stack on this build, innermost first, is:

```text
ucrtbase fwrite
Acrobat.dll+0x560567
Acrobat.dll+0x5604BD
Acrobat.dll+0x6BB282
Acrobat.dll+0x6BAB1B
Acrobat.dll+0x28B40D
Acrobat.dll+0x28B159
Acrobat.dll+0x2521D7
Acrobat.dll+0x4C5DDE
Acrobat.dll+0x4C5C4C
```

The interesting frame is `0x6BB282`, inside the NGL initializer. The code just before
the batch is written is the decision sequence at `0x6BB0EB`. That call target is
`InitializeWorkflows`.

The same technique on the `InitializeWorkflows: invoked` line in the client log gives
the return address `0x6E270B` inside the callee, which confirms the function start at
`0x6E248C`.

### 5.3 Resolve the function boundary

`.pdata` holds a sorted array of `RUNTIME_FUNCTION` records, 12 bytes each:
`BeginAddress`, `EndAddress`, `UnwindInfoAddress`, all RVAs. Read the section header
for `.pdata`, parse the records, and binary search the address from the backtrace. On
this build:

```text
0x6BAC1C - 0x6BB3BE   NGL initializer, caller of InitializeWorkflows
0x6E248C - 0x6E2DB5   InitializeWorkflows
0x6DA6C4 - 0x6DA7A5   entitlement mapper
0x7DBE80 - 0x7DC056   level gate
0x8F1DB0 - 0x8F5BFE   workflow launcher, contains CreateProcessW
```

A function start is where the prologue begins. For `InitializeWorkflows` the prologue
is `48 8B C4 ...`, a frame-pointer copy that appears once at the start. The return
address from the call site lands 5 bytes after the call, so subtract the call encoding
to find the target, then walk back to the nearest `.pdata` start.

### 5.4 Find the mapper without a backtrace

If the log backtrace is unavailable, anchor on the strings. The `.rdata` cluster at
`0x364AFF0` contains:

```text
0x364AFF0  Entitlement is %d
0x364B008  Entitlement is Reader/Residue.
0x364B040  Entitlement is Acrobat Standard.
0x364B068  Entitlement is Acrobat Professional.
0x364B090  Entitlement is UNKNOWN.
```

Find the code that references the `%d` formatter or the Reader/Residue sentence in the
same function. The mapper is a short function immediately before that formatter, and
its distinguishing bytes are `BB 01 00 00 00 E8` with a call immediately after the
literal. On 25.1 that is `0x6DA6D1`.

Do not confuse the mapper with the notification log at `0x6DA9BF`. The notification
function compares `ebx` against 1 and chooses a sentence. It does not change the level.

### 5.5 Sanity checks before writing

Write only if all of these are true:

- The original bytes at the site match the table in phase 3 exactly.
- The site is inside the function boundary from `.pdata`, not in a thunk or a data
  table.
- The patched range does not cross a basic block that another branch enters mid-way.
  Both patches are shorter than or equal to the original instruction, so this is
  satisfied by construction.
- No Acrobat process holds the file open. Windows blocks the write or the loader keeps
  the old image otherwise.

---

## 6. Apply

Order matters: back up, write, read back, then launch. Never launch between the two
writes.

1. Close every Acrobat process, including `acrotray.exe`, `AdobeCollabSync.exe`, and
   any `adobe_licensing_wf_acro.exe`.
2. Copy `Acrobat.dll` to a backup outside the install directory. Keep the original
   hash. The repository reference is `Acrobat.dll.orig-procrack`.
3. Open the file for read/write and write the first range at file offset `0x6D9AD1`:
   `BB 2C 01 00 00`.
4. Write the second range at file offset `0x6E188C`: `33 C0 C3`.
5. Seek back and read both ranges. They must equal the patch bytes. If either read
   differs, stop and restore.
6. Record the patched SHA-256. It is the build identity for future runs.

On this build the result is:

```text
size            79,011,288
patched SHA256  4FC9D1DC55EAE69637D3E13E8E55F04CABCA58C0747E8983DCF91A6B857BB3BE
```

Program Files is writable only by an administrator. A medium-integrity session cannot
write the DLL; the file operation must run elevated. The copy-tree route avoids the
elevation but changes the install resolution and is not equivalent.

---

## 7. Verification matrix

Run every row. A pass is all rows, not the first one.

### 7.1 Entitlement

Launch on a PDF, wait for the licensing batch to flush, and read the NGL log:

```text
Entitlement is 300
ACROBAT LICENSE CHANGE NOTIFICATION : Entitlement is Acrobat Professional.
```

Read the registry value:

```text
HKCU\SOFTWARE\Adobe\Adobe Acrobat\DC\AVEntitlement
  iEntitlementLevel = 300 (DWORD)
```

Restart once. The value must still be 300 after the restart. If it returns to 1, the
mapper patch is not in the running image: check that the process loaded the patched
DLL and not a cached copy from another directory.

### 7.2 Product mode

Open a PDF whose `/OpenAction` runs a JavaScript alert with `app.viewerType`. The
expected value is:

```text
VIEWERTYPE=Exchange-Pro
```

`Reader` means the level patch is absent or the process is Reader mode.
`Exchange` means Standard, which is 100, not 300.

### 7.3 A Pro-only operation

In the same OpenAction, call `addWatermarkFromText` with a text string and catch the
exception. Acrobat Professional returns without error and the watermark appears on the
page. Reader throws a security error. This is the row that separates a real
entitlement from a cosmetic log line.

```text
VIEWERTYPE=Exchange-Pro | WATERMARK=OK
```

### 7.4 No workflow host

Cold start on a PDF and watch for 60 seconds:

- no `adobe_licensing_wf_acro.exe` in the process list at any sample;
- no top-level window with class `EmbeddedWB` titled `Adobe Acrobat`;
- the main window answers a `WM_NULL` with `SendMessageTimeout` in under one second at
  every sample;
- the window title is the document name, not a trial or sign-in surface.

A host that appears and exits is a failure of the initializer patch, even if the sheet
does not have time to paint. A window that stops answering messages means the patch
was applied to the launcher instead of the initializer.

### 7.5 Disk state

Read both ranges from the file on disk after the run, not only from the process. If
Windows Installer repaired the product during the run, the file reverts and the next
cold start fails. Keep the backup until this row passes twice.

---

## 8. Failure modes

| Symptom | Cause | Fix |
|---|---|---|
| Log still says `Entitlement is 1` | mapper patch missing or wrong file | verify bytes at `0x6D9AD1`, verify loaded DLL path |
| Level is 300 but the trial sheet still appears | only the mapper was patched | apply the initializer patch |
| Sheet gone, window frozen | host killed or stubbed instead of never started | patch `InitializeWorkflows`, restore the real host binary |
| `app.viewerType` returns `Reader` | level gate saw a value below 100 | check the mapper and the registry write-back |
| `addWatermarkFromText` throws | entitlement not actually Professional | the log line was cosmetic; go back to 7.1 and 7.2 |
| Patch reverts after a reboot or update | installer repair or update replaced the DLL | reapply, or restore and redo on the new build |
| Write returns access denied | medium integrity | run the write elevated |
| Two `Acrobat.dll` images in the process | copy-tree launch | use the installed binary |

---

## 9. Updates and rollback

An Acrobat update replaces `Acrobat.dll`. The two RVAs are not stable across builds.
Before reapplying, check the original bytes at both sites and the function boundaries
from `.pdata`. If the bytes differ, run phase 5 again.

Rollback is a file copy:

1. Close every Acrobat process.
2. Copy `Acrobat.dll.orig-procrack` over `Acrobat.dll`.
3. Confirm the pristine SHA-256.
4. Start Acrobat once and confirm the Reader verdict returns.

A rollback does not require a reboot. The loader reads the file on the next start.

---

## 10. Boundaries

- Do not forge, edit, or replay the NGL profile. It is signed and keyed; a local edit
  cannot survive validation, and a copied profile is bound to another device.
- Do not ship a patched DLL, an installer, or a patcher. The repository publishes the
  guide and the offsets only.
- Do not patch the notification formatter at `0x6DA9BF` and call it done. It changes a
  sentence, not a capability.
- Do not target the CEF host binary. It is a renderer; the decision is in the parent.
- Do not reuse these RVAs on 25.2 or on the 32-bit Reader line. The model transfers,
  the addresses do not.

---

## 11. Agent fast path

For an agent that only needs the result on this exact build:

1. Confirm the DLL hash or the original bytes.
2. Write `BB 2C 01 00 00` at file offset `0x6D9AD1`.
3. Write `33 C0 C3` at file offset `0x6E188C`.
4. Read both back.
5. Launch, then check `Entitlement is 300`, `viewerType=Exchange-Pro`, watermark OK,
   and 60 seconds with no `adobe_licensing_wf_acro.exe`.

That is the whole crack. The rest of this document exists so the next build can be
solved the same way instead of guessed.
