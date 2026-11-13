# Contributing

Jailbreak is a domain-organized library. Add a project as a self-contained folder under `domains/`, not as a new section in the root README.

## Automation

Use the jailbreak skill and its scripts:

```text
skills/jailbreak/SKILL.md
skills/jailbreak/scripts/new-project.mjs
skills/jailbreak/scripts/check-repo.mjs
skills/jailbreak/scripts/hash.mjs
```

Scaffold a project:

```bash
node skills/jailbreak/scripts/new-project.mjs --domain <domain> --project <project> --title "<title>"
```

Run the repository checks before commit:

```bash
node skills/jailbreak/scripts/check-repo.mjs
```

## Folder layout

```text
domains/
  <domain>/
    <project>/
      README.md
      playbook.md
      patcher/
        src/
          <source only>
      legacy/
        <optional old scripts>
```

Use lowercase and hyphens:

```text
domains/disk-and-partition/example-tool/
domains/games/example-game/
domains/development-tools/example-ide/
```

## Domains

Pick the closest existing domain:

| Domain | Scope |
|---|---|
| `disk-and-partition` | Partition managers, disk imaging, filesystem tools |
| `system-utilities` | Drivers, cleanup, backup, recovery, OS tools |
| `media-and-graphics` | Editors, converters, renderers, asset tools |
| `games` | Game clients, engines, mod loaders, single-player tools |
| `development-tools` | IDEs, compilers, debuggers, SDKs |
| `security-and-networking` | Network tools, packet analysis, local security research |
| `internet-and-downloads` | Download managers, sync clients, internet utilities |
| `productivity` | Office, PDF, workflow, automation |
| `other` | Anything that does not fit yet |

Create a new domain only when a project does not fit any existing one. Keep domain names short and lowercase.

## Project README

Every project needs a `README.md` with:

- Project name and domain
- Supported version or build range
- Current status: untested, desktop verified, or desktop and secondary environment verified
- Files in the folder
- Quick start
- Known limitations and update behavior
- Link to the playbook
- License note

## Playbook

A playbook must let another engineer recreate the result without guessing. Include:

- Target architecture, file names, and install layout
- File size and SHA256 for the reference build
- Exact addresses: RVA, file offset, original bytes, patched bytes
- How the protection works
- How to find the same sites in a new version
- RTTI names, vtable layout, or code anchors
- Edition values or license state values
- Verification steps
- Rollback steps
- Secondary media or packaging steps, if applicable

Prefer concrete data over narrative. Include commands and small scripts.

## Tooling

If you publish a patcher source:

- Put the source in `patcher/src/`
- Include build instructions
- State the exact target build and hash
- Refuse unknown builds instead of patching blindly
- Verify after writing
- Keep a rollback path

Do not commit a compiled patcher, a keygen, a license generator, a pre-patched binary, a commercial binary, an installer, or a copyrighted application file. Ship patches, source, and documentation. For vendors that actively enforce their licenses, publish the guide only and keep all tooling local.

## Root README

The root README is generic. Do not add a project list, a changelog of projects, or links to individual projects there. Projects are discovered by browsing `domains/`.

## License

Contributions are accepted under the MIT License in [`LICENSE`](LICENSE). By opening a pull request, you agree to publish your contribution under the same license.
