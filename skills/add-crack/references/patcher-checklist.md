# Patcher Checklist

Use this checklist for every standalone patcher added to the repository.

## Build lock

- [ ] Target file size is checked exactly.
- [ ] Target SHA256 is checked for the pristine build, or every patch site is byte-checked.
- [ ] Unknown builds are refused before any write.
- [ ] The patcher does not use `--force` to write at old offsets.
- [ ] The target version is printed in the UI or console.

## Safety

- [ ] The patcher requires administrator rights through the manifest.
- [ ] It refuses to write while the target process is running.
- [ ] It creates a pristine backup outside the install directory.
- [ ] It never writes the backup into the install directory.
- [ ] It writes through a temp file and an atomic replace, or an equally safe swap.
- [ ] It restores file attributes if the target was read-only.

## Operations

- [ ] `Check` prints size, SHA256, and the state of every patch site.
- [ ] `Apply` patches every required site and verifies each one after writing.
- [ ] `Apply` is idempotent. A second run is a no-op.
- [ ] `Restore` requires a pristine backup that matches the expected hash.
- [ ] `Restore` verifies the result.
- [ ] The UI names each patch site and its offset.
- [ ] Errors are specific: unsupported size, unsupported bytes, process running, access denied.

## Packaging

- [ ] Source is included under `patcher/src/`.
- [ ] A one-command build script is included.
- [ ] The build script uses only tools that ship with Windows or are documented.
- [ ] The binary is small and has no external runtime installer.
- [ ] No telemetry, analytics, or network calls.
- [ ] A short `README-Patcher.txt` explains run, check, apply, restore, and build.

## Test matrix

- [ ] Pristine copy: `Apply` produces the expected patched SHA256.
- [ ] Patched copy: `Apply` reports already patched and changes nothing.
- [ ] Unknown build: `Apply` refuses and leaves the file untouched.
- [ ] Running target: `Apply` refuses.
- [ ] `Restore` returns the pristine SHA256.
- [ ] Restored app launches normally.
- [ ] Patched app launches normally.
- [ ] Secondary environment, if applicable, launches with the patch.

## Repository hygiene

- [ ] No personal paths in source, docs, or binary strings.
- [ ] No commercial application binaries are committed.
- [ ] The project README links to the playbook.
- [ ] The root README is unchanged except for a generic domain or automation link.
