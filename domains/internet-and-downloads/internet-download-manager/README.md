# Internet Download Manager

Domain: `internet-and-downloads`

Target: Internet Download Manager 6.x, 32-bit native builds. The worked example is 6.43 build 18.

This is a method, not a fixed patch list. The playbook explains how to find and patch the license checks, registration UI, exit paths, crypt32 lifetime, and helper dialogs in any build. The offsets in the worked example are a reference for one build, not a contract for the next one.

## What is included

| File | Purpose |
|---|---|
| `playbook.md` | Full discovery and patch workflow, generic patcher, version drift guide, verification matrix |
| `README.md` | Entry point and layer summary |

## Read this first

1. Work on a copy in a VM. Keep a pristine backup of `IDMan.exe` and `IDMGrHlp.exe`.
2. Identify the version from the file resource, the `idmvers` registry value, and the About dialog.
3. Follow the layer discovery in the playbook. Do not start by copying offsets.
4. Record every patch in a JSON manifest with the original bytes and the patch bytes.
5. Build with the generic patcher in playbook section 10. It applies offset or pattern patches and recomputes the PE checksum.
6. Run the verification matrix in playbook section 13. A build is not done until every applicable check passes.

## Layers

| Layer | What to do |
|---|---|
| Registry | Set `Serial`, `FName`, `LName`, `Email`, `idmvers`, and `ExePath`. Use a random synthetic serial. |
| Validators | Make the name and serial validators return true. |
| Status | Force the registered path, or leave the status function alone and suppress the UI. |
| Registration UI | Redirect the registration dialog procedure to a cave that closes the title-length 38 dialog. |
| Warning and licensed-to | Patch the warning function and skip the licensed-to call. |
| Buy page and update | Patch the URL builder, the `ShellExecute` call, and the update check. |
| Lifecycle | Disable the quit and exit paths, and hide the window on `WM_CLOSE`. |
| Crypt32 | Remove the unload of the cached crypt32 handle, or hold a reference at the entry point. |
| Helper | Skip the `MessageBox` calls in `IDMGrHlp.exe`. |
| Checksum | Recompute the PE checksum after every code patch. |

## Version drift

Playbook section 11 lists the stable anchors for each layer and the method to re-find it after an update. The short version:

- Offsets move. Strings, imports, registry names, serial format constants, dialog titles, and status codes stay useful.
- Start from the string or the API call, not from the old address.
- Patch one layer at a time on a copy, then build a manifest.
- Re-run the full verification after every update.

Playbook section 12 is a reference map for 6.43 build 18 only. Use it when you have confirmed that exact build.

## Distribution

This repository ships the method and the patcher, not a patched binary. Do not commit a patched `IDMan.exe`, a keygen, or a compiled patcher.
