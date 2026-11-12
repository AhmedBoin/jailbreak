---
name: add-crack
description: Add a new crack or patch project to the Jailbreak repository. Use when reverse engineering a target, writing the playbook, building a standalone patcher, verifying desktop and WinPE behavior, and publishing under domains/<domain>/<project>/.
---

# Add Crack

Use this skill to add one complete project to the Jailbreak repository: a domain folder, a project README, a reverse engineering playbook, optional patcher source and binaries, verification notes, and a clean commit.

Read these when you reach the matching step:

- `references/playbook-template.md` for the playbook structure.
- `references/patcher-checklist.md` for patcher requirements and tests.
- `scripts/new-project.ps1` to scaffold a project.
- `scripts/check-repo.ps1` before commit.

Run commands from the repository root.

## 1. Preconditions

- The target application is installed locally and can be launched.
- You can read and write the install directory. Run tools elevated when needed.
- The target is a native or managed binary, not a remote service you do not control.
- The repository is cloned. `README.md`, `LICENSE`, and `domains/` exist.

Useful tools, in order of preference:

- `radare2` or `rizin` for fast RTTI and xref discovery.
- IDA Professional or Ghidra for decompilation.
- `x64dbg` for runtime checks.
- `pefile` and `capstone` for PE parsing and patching.
- The .NET Framework `csc.exe` for a dependency-free Windows patcher.
- `oscdimg` or the target's own media builder for WinPE ISO work.

## 2. Pick the domain and project slug

Choose the closest domain from the root `README.md`. Create a new domain only when nothing fits.

Project path:

```text
domains/<domain>/<project>/
```

Rules:

- Lowercase.
- Hyphens, no spaces.
- Short but specific, for example `minitool-partition-wizard`.
- Do not put the version in the slug unless the project is version-specific by design.

Scaffold:

```powershell
powershell -ExecutionPolicy Bypass -File skills/add-crack/scripts/new-project.ps1 `
  -Domain disk-and-partition `
  -Project example-tool `
  -Title "Example Tool" `
  -Version "1.0" `
  -Summary "One-line description of the target and the patch."
```

The script creates:

```text
domains/<domain>/<project>/
  README.md
  playbook.md
```

Add `patcher/` and `legacy/` only when you have something to put in them.

## 3. Triage the target

Record:

- Install path and main executable.
- Version string from the executable, About dialog, or file metadata.
- Architecture: x86, x64, ARM64.
- Framework: native C++, .NET, Qt, Electron, Java, Python bundle.
- Packer or protector: none, UPX, VMProtect, Themida, custom.
- License UI: trial counter, register dialog, edition in the title bar, feature gates.
- Update mechanism: in-app updater, scheduled task, service, download URL.
- Boot media or PE variant, if the product creates one.

Hash the main binary before modifying it:

```powershell
Get-FileHash .\target.exe -Algorithm SHA256
Get-Item .\target.exe | Select-Object Length
```

If the target is packed, unpack it first. A playbook that patches a packed stub without understanding the unpacking step is incomplete.

## 4. Locate the license logic

Work from visible behavior back to code:

1. Search strings for `register`, `trial`, `license`, `activation`, `edition`, `upgrade`, `expired`, and the exact dialog text.
2. Find xrefs to those strings in a disassembler.
3. Look for RTTI class names such as `LicenseManager`, `LicenseChecker`, `IsRegistered`, `GetLicenseType`, `TrialChecker`.
4. Find the vtable for each checker. The common layout is destructor at `+0x00`, `IsRegistered` at `+0x08`, `GetLicenseType` at `+0x10`.
5. Follow vtable thunks until you reach the implementation.
6. Confirm the return type: bool in `AL`, int in `EAX`.
7. Check whether a second checker exists for boot media, portable mode, or a different SKU.

Prefer function-level stubs over branch edits:

```text
IsRegistered  ->  B0 01 C3              mov al,1 ; ret
GetLicenseType -> B8 08 00 00 00 C3     mov eax,8 ; ret
```

Use the real edition value from the target's edition switch. Do not invent one.

If the target has multiple checkers, patch all of them. A desktop-only patch that leaves the WinPE checker intact will fail when the user boots the media.

## 5. Write the playbook

Fill `playbook.md` from `references/playbook-template.md`. New projects use `playbook.md`; existing projects may keep a descriptive `*Playbook*.md` filename.

The playbook must include:

- Target profile and install layout.
- Reference build size and SHA256.
- Protection analysis.
- Exact RVA, file offset, original bytes, and patch bytes for every site.
- How to find the same sites in a new version.
- RTTI names, vtable layout, strings, or other anchors.
- Edition or license state values.
- Verification steps.
- Rollback steps.
- Boot media or packaging steps.

Another engineer must be able to recreate the patch from the playbook without asking questions.

## 6. Build the patcher

Read `references/patcher-checklist.md`.

Preferred shape:

```text
patcher/
  ToolPatcher.exe
  README-Patcher.txt
  src/
    PatcherCore.cs
    PatcherMain.cs
    app.manifest
    build.cmd
```

Requirements:

- Build-locked to a known size and byte state.
- Refuses unknown builds with a clear message.
- `Check`, `Apply`, and `Restore`.
- Creates a pristine backup outside the install directory.
- Requires administrator rights through the manifest.
- Refuses to write while the target process is running.
- Verifies every patch after writing.
- Uses an atomic replace or a safe temp-file swap.
- Includes source and a one-command build script.
- No telemetry, no network calls, no external runtime installer.

For a Windows-only patcher, compile C# with the .NET Framework compiler that ships with Windows:

```cmd
%WINDIR%\Microsoft.NET\Framework64\v4.0.30319\csc.exe ^
  /target:winexe /platform:anycpu /optimize+ /langversion:5 ^
  /win32manifest:app.manifest /out:ToolPatcher.exe ^
  /r:System.dll /r:System.Windows.Forms.dll /r:System.Drawing.dll ^
  PatcherCore.cs PatcherMain.cs
```

## 7. Verify

Desktop:

- Launch the patched app.
- Confirm the title bar or About dialog shows the expected edition.
- Open a feature that was previously gated.
- Confirm the register or upgrade prompt is gone.

Boot media or secondary environment:

- Rebuild the media with the patched binary.
- Boot it in a VM or on a spare machine.
- Confirm the registration error is gone and the expected edition is active.

Patcher:

- Apply to a pristine copy and compare the resulting SHA256 with the expected patched hash.
- Apply again. It must be a no-op.
- Feed an unknown build. It must refuse without writing.
- Restore. The hash must return to the pristine value.
- Run it while the target is open. It must refuse.

Add the results to the project README and playbook.

## 8. Sanitize

Before commit, remove from every tracked file:

- User profile roots and any path under a personal home directory.
- Desktop paths and local backup folders.
- Personal names, usernames, email addresses, and machine names.
- Local backup folder names that only exist on one machine.
- Absolute paths that should be placeholders.

Use placeholders such as `<version>`, `<install-dir>`, `<iso-root>`, `<mount-dir>`, and `%ProgramData%`.

Run:

```powershell
powershell -ExecutionPolicy Bypass -File skills/add-crack/scripts/check-repo.ps1
```

Fix every failure before committing.

## 9. Commit and publish

Set a public-safe author for this repository only:

```powershell
git config user.name "AhmedBoin"
git config user.email "AhmedBoin@users.noreply.github.com"
```

Stage, commit, and push:

```powershell
git add domains/<domain>/<project>
git add README.md
git commit -m "Add <project> playbook and patcher"
git push
```

Use a specific commit message. Do not commit a whole drive.

Verify the remote:

```powershell
git log -1 --format="%H%n%an <%ae>%n%s"
git ls-tree -r --name-only HEAD
```

The remote tree must contain the project README, playbook, patcher source, and any shipped binary. It must not contain personal paths or commercial application files.

## 10. Definition of done

- Project is under `domains/<domain>/<project>/`.
- `README.md` explains the target, status, files, quick start, and update behavior.
- `playbook.md` has exact offsets, bytes, discovery steps, verification, and rollback.
- Patcher source and binary are present if a patcher is shipped.
- Patcher is build-locked and refuses unknown builds.
- Desktop and secondary environment are both verified when applicable.
- No personal paths or identifying data.
- Root README remains generic and has no project list.
- `check-repo.ps1` passes.
- Commit is pushed and verified.

## 11. Common failures

- Patching a thunk instead of the implementation, or the reverse, without checking the call path.
- Patching only the desktop checker and forgetting the WinPE checker.
- Reusing offsets from an old version without a size or hash guard.
- Shipping a patcher that silently corrupts a new build.
- Leaving the pristine backup inside the install directory and then embedding it in boot media.
- Adding a project list to the root README.
- Committing installers, DLLs, or other commercial binaries.
- Leaving a local user path in the playbook or source.
