# Contributing

Jailbreak is a domain-organized library. Add a project as a self-contained folder under `domains/`, not as a new section in the root README.

## Automation

Use the add-crack skill and its scripts:

```text
skills/add-crack/SKILL.md
skills/add-crack/scripts/new-project.ps1
skills/add-crack/scripts/check-repo.ps1
```

Scaffold a project:

```powershell
powershell -ExecutionPolicy Bypass -File skills/add-crack/scripts/new-project.ps1 -Domain <domain> -Project <project> -Title "<title>"
```

Run the repository checks before commit:

```powershell
powershell -ExecutionPolicy Bypass -File skills/add-crack/scripts/check-repo.ps1
```

## Folder layout

```text
domains/
  <domain>/
    <project>/
      README.md
      playbook.md
      patcher/
        <patcher files>
      legacy/
        <optional old scripts>
```

Use lowercase and hyphens:

```text
domains/disk-and-partition/minitool-partition-wizard/
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
| `productivity` | Office, PDF, workflow, automation |
| `other` | Anything that does not fit yet |

Create a new domain only when a project does not fit any existing one. Keep domain names short and lowercase.

## Project README

Every project needs a `README.md` with:

- Project name and domain
- Supported version or build range
- Current status: untested, desktop verified, or desktop and PE verified
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
- Boot media or packaging steps, if applicable

Prefer concrete data over narrative. Include commands and small scripts.

## Tooling

If you ship a patcher or crack:

- Put it in `patcher/`
- Include source code and build instructions
- State the exact target build and hash
- Refuse unknown builds instead of patching blindly
- Verify after writing
- Keep a rollback path

Do not commit commercial binaries, installers, or copyrighted application files. Ship patches, scripts, source, and documentation.

## Root README

The root README is generic. Do not add a project list, a changelog of projects, or links to individual projects there. Projects are discovered by browsing `domains/`.

## License

Contributions are accepted under the MIT License in [`LICENSE`](LICENSE). By opening a pull request, you agree to publish your contribution under the same license.
