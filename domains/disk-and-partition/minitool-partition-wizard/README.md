# MiniTool Partition Wizard

Domain: `disk-and-partition`

Target: MiniTool Partition Wizard 13.9, native x64 build.

Status: desktop and WinPE verified.

This project is a guide only. The compiled patcher, patcher source, and legacy script are not in the repository.

## What is included

| File | Purpose |
|---|---|
| `MiniTool Partition Wizard Crack Playbook.md` | Full analysis, offsets, discovery workflow, WinPE details, ISO rebuild |
| `README.md` | Scope, patch summary, and quick start |

## Quick start

1. Close `partitionwizard.exe`.
2. Back up `partitionwizard.dll` outside the install directory.
3. Apply the four byte patches below with a local hex editor or a local script.
4. Rebuild the bootable media from the app so `boot.wim` receives the patched DLL.
5. Verify the desktop title bar and the WinPE boot.

The four patches are:

| Checker | Method | 13.9 file offset | Patch |
|---|---|---:|---|
| Desktop | `IsRegistered` | `0x13DBA0` | `B0 01 C3` |
| Desktop | `GetLicenseType` | `0x13F8F0` | `B8 08 00 00 00 C3` |
| WinPE | `IsRegistered` | `0x13C860` | `B0 01 C3` |
| WinPE | `GetLicenseType` | `0x13E590` | `B8 08 00 00 00 C3` |

## Reference build

```text
size            8,432,880 bytes
pristine SHA256 02ED32946FFA02F938107B9BFF233B1E063F38762A553BD209F698B4E07E650D
patched SHA256  8B4442B4F5816530AE6B3CBB842133FB246737AB57AF714F5267B59F55A093BA
```

Any local tooling should refuse unknown sizes or unknown bytes. For a new build, use the discovery workflow in the playbook and update the four RVAs.

## Bootable media

The bootable media uses `KWinPELicenseChecker`, a separate checker from the desktop build. Patching only the desktop pair produces:

```text
Only registered version can be run in Windows PE environment.
```

The playbook covers the PE checker, the `boot.wim` layout, and the `oscdimg` command.

## Updates

A MiniTool update replaces `partitionwizard.dll` and removes the patches. The existing boot ISO keeps its own old DLL and remains patched, but it does not contain the new version.

Re-apply the four patches after an update, then rebuild the boot media.

## Full playbook

Open [`MiniTool Partition Wizard Crack Playbook.md`](MiniTool%20Partition%20Wizard%20Crack%20Playbook.md).

## License

MIT. See the repository [`LICENSE`](../../../LICENSE).
