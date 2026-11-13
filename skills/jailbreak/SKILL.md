---
name: jailbreak
description: Add a new crack or patch project to the Jailbreak repository. Use when reverse engineering a desktop target on any OS, writing the playbook, building a standalone patcher, verifying desktop and secondary media behavior, and publishing under domains/<domain>/<project>/.
---

# Jailbreak

Use this skill to add one complete project to the Jailbreak repository: a domain folder, a project README, a reverse engineering playbook, optional patcher source, verification notes, and a clean commit.

The workflow is plain Markdown and works on Windows, macOS, and Linux in any agent harness. The helper scripts are optional Node scripts (Node 16 or newer). If Node is not available, do the same steps by hand.

Read these when you reach the matching step:

- `references/playbook-template.md` for the playbook structure.
- `references/patcher-checklist.md` for patcher requirements and tests.
- `scripts/new-project.mjs` to scaffold a project.
- `scripts/check-repo.mjs` before commit.
- `scripts/hash.mjs` for SHA256 and size.

Resolve `references/` and `scripts/` relative to this `SKILL.md`. In the Jailbreak repository, the same files are under `skills/jailbreak/`.

Run commands from the repository root.

## 0. Distribution policy

This repository publishes analysis and guides, not ready-to-run cracks.

- Never commit a pre-patched commercial binary, a keygen, a license generator, or a compiled patcher.
- Commit the playbook, the project README, and optional source that a user builds locally.
- For vendors that actively enforce their licenses, publish the guide only and keep all tooling local.
- A playbook may contain offsets, byte patterns, and verification steps. It must not contain a commercial installer, a patched build, or a license key.
- The repository check rejects compiled patchers and pre-patched binaries. Do not add an exception.

## 1. Preconditions

- The target application is installed locally and can be launched.
- You can read and write the install location. Use elevated rights when the target platform requires them.
- The target is a native or managed binary you control locally, not a remote service.
- The repository is cloned. `README.md`, `LICENSE`, and `domains/` exist.

Useful tools, in order of preference:

- `radare2` or `rizin` for fast RTTI and xref discovery.
- IDA Professional or Ghidra for decompilation.
- A debugger for the platform: x64dbg or WinDbg on Windows, LLDB on macOS, gdb or LLDB on Linux.
- `LIEF`, `pefile`, `macholib`, `readelf`, `objdump`, or `otool` for file format work and patching.
- A compiler or runtime you already use for the patcher. Any language is fine.
- The product's own media builder, or the platform image tools, for boot media.

## 2. Pick the domain and project slug

Choose the closest domain from the root `README.md`. Create a new domain only when nothing fits.

Project path:

```text
domains/<domain>/<project>/
```

Rules:

- Lowercase.
- Hyphens, no spaces.
- Short but specific, for example `example-partition-manager`.
- Do not put the version in the slug unless the project is version-specific by design.

Scaffold:

```bash
node skills/jailbreak/scripts/new-project.mjs \
  --domain disk-and-partition \
  --project example-tool \
  --title "Example Tool" \
  --version "1.0" \
  --summary "One-line description of the target and the patch."
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

- Install location and main executable.
- Version string from the executable, About dialog, or file metadata.
- File format and architecture: PE x86, x64, or ARM64; Mach-O thin, fat, or universal; ELF; managed .NET, JVM, Electron, or a Python bundle.
- Packer or protector: none, UPX, VMProtect, Themida, custom.
- Code signature: Authenticode, Apple code signing and notarization, package signatures, or none. Note whether the target verifies its own signature or file hashes after patching.
- License UI: trial counter, register dialog, edition in the title bar, feature gates.
- Update mechanism: in-app updater, scheduled task, service, download URL.
- Secondary media or portable mode, if the product creates one.

Hash the main binary before modifying it:

```bash
node skills/jailbreak/scripts/hash.mjs ./target
```

The script prints uppercase SHA256, size in bytes, and the path. If the target is packed, unpack it first. A playbook that patches a packed stub without understanding the unpacking step is incomplete.

## 4. Locate the license logic

Work from visible behavior back to code:

1. Search strings for `register`, `trial`, `license`, `activation`, `edition`, `upgrade`, `expired`, and the exact dialog text.
2. Find xrefs to those strings in a disassembler.
3. Look for class metadata such as `LicenseManager`, `LicenseChecker`, `IsRegistered`, `GetLicenseType`, `TrialChecker`. The metadata format depends on the toolchain: MSVC RTTI on Windows, the Itanium C++ ABI on macOS and Linux, Swift or Objective-C metadata on Apple platforms, and assembly metadata for .NET.
4. Find the vtable for each checker. A common layout is destructor at `+0x00`, `IsRegistered` at `+0x08`, `GetLicenseType` at `+0x10`. Confirm it for the target; do not assume it.
5. Follow vtable thunks until you reach the implementation.
6. Confirm the return type: bool in `AL`, `EAX`, or `W0`, depending on architecture.
7. Check whether a second checker exists for boot media, portable mode, or a different SKU.

Prefer function-level stubs over branch edits. The bytes are architecture-specific:

```text
x86 and x64
  IsRegistered   -> B0 01 C3              mov al,1 ; ret
  GetLicenseType -> B8 08 00 00 00 C3     mov eax,8 ; ret

ARM64
  IsRegistered   -> 20 00 80 52 C0 03 5F D6    mov w0,1 ; ret
```

Use the real edition value from the target's edition switch. Do not invent one.

If the target has multiple checkers, patch all of them. A desktop-only patch that leaves the boot media checker intact will fail when the user boots the media.

## 5. Write the playbook

Fill `playbook.md` from `references/playbook-template.md`. New projects use `playbook.md`; existing projects may keep a descriptive `*Playbook*.md` filename.

The playbook must include:

- Target profile and install layout.
- Reference build size and SHA256.
- Protection analysis.
- Exact RVA, file offset, original bytes, and patch bytes for every site.
- How to find the same sites in a new version.
- Class names, vtable layout, strings, or other anchors.
- Edition or license state values.
- Verification steps.
- Rollback steps.
- Boot media or packaging steps.

Another engineer must be able to recreate the patch from the playbook without asking questions.

## 6. Build the patcher locally

Read `references/patcher-checklist.md`.

A typical shape, in any language:

```text
patcher/
  README-Patcher.txt
  src/
    <patcher source>
  build.<ext>
```

The compiled executable is a local artifact. It is not committed to the repository.

Requirements:

- Build-locked to a known size and byte state.
- Refuses unknown builds with a clear message.
- `Check`, `Apply`, and `Restore`.
- Creates a pristine backup outside the install directory.
- Requests elevated rights when the platform requires them.
- Refuses to write while the target process is running.
- Verifies every patch after writing.
- Uses an atomic replace or a safe temp-file swap.
- Includes source and a one-command build script; the compiled binary stays outside the repository.
- No telemetry, no network calls, no external runtime installer.

Platform notes:

- Windows may check Authenticode only at load time.
- macOS may refuse a modified Mach-O under hardened runtime. Re-sign ad hoc, or target a build that does not enforce the signature.
- Linux package managers may verify file hashes or signatures. State this in the playbook when it applies.

## 7. Verify

Desktop:

- Launch the patched app.
- Confirm the title bar or About dialog shows the expected edition.
- Open a feature that was previously gated.
- Confirm the register or upgrade prompt is gone.

Secondary environment or boot media:

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
- Desktop and cloud folder paths, and local backup folders.
- Personal names, usernames, email addresses, and machine names.
- Local backup folder names that only exist on one machine.
- Absolute paths that should be placeholders.

Use placeholders such as `<version>`, `<install-dir>`, `<media-root>`, `<mount-dir>`, and `<data-dir>`.

Run:

```bash
node skills/jailbreak/scripts/check-repo.mjs
```

Fix every failure before committing.

## 9. Commit and publish

Set a public-safe author for this repository only:

```bash
git config user.name "<public-author>"
git config user.email "<id>@users.noreply.github.com"
```

Stage, commit, and push:

```bash
git add domains/<domain>/<project>
git add README.md
git commit -m "Add <project> playbook and patcher"
git push
```

Use a specific commit message. Do not commit a whole drive.

Verify the remote:

```bash
git log -1 --format="%H%n%an <%ae>%n%s"
git ls-tree -r --name-only HEAD
```

The remote tree must contain the project README, the playbook, and patcher source only when it is published. It must not contain a compiled patcher, a pre-patched binary, a keygen, personal paths, or commercial application files.

## 10. Definition of done

- Project is under `domains/<domain>/<project>/`.
- `README.md` explains the target, status, files, quick start, and update behavior.
- `playbook.md` has exact offsets, bytes, discovery steps, verification, and rollback.
- Patcher source is present only when it is published; no compiled patcher or pre-patched binary is committed.
- Patcher is build-locked and refuses unknown builds when source is published.
- Desktop and secondary environment are both verified when applicable.
- No personal paths or identifying data.
- Root README remains generic and has no project list.
- `node skills/jailbreak/scripts/check-repo.mjs` passes.
- Commit is pushed and verified.

## 11. Common failures

- Patching a thunk instead of the implementation, or the reverse, without checking the call path.
- Patching only the desktop checker and forgetting the boot media checker.
- Reusing offsets from an old version without a size or hash guard.
- Shipping a patcher that silently corrupts a new build.
- Leaving the pristine backup inside the install directory and then embedding it in boot media.
- Adding a project list to the root README.
- Committing installers, DLLs, or other commercial binaries.
- Committing a compiled patcher, a keygen, a license generator, or a pre-patched binary.
- Leaving a local user path in the playbook or source.
