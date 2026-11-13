# Install the jailbreak skill

The canonical skill is:

```text
skills/jailbreak/
  SKILL.md
  references/
    playbook-template.md
    patcher-checklist.md
    project-readme-template.md
  scripts/
    new-project.mjs
    check-repo.mjs
    hash.mjs
```

The skill body is plain Markdown and works in any harness on any OS. The scripts are optional Node 16+ helpers; without Node, follow the same steps by hand.

The repository commits one canonical copy of the skill. Install it by copying the `skills/jailbreak` folder into the harness skills directory; no per-harness copies live in the repository.

## Any harness with a skills directory

Copy the `skills/jailbreak` folder into the harness skills directory. At the repository root, a POSIX shell example:

```bash
mkdir -p ~/.config/opencode/skills
cp -r skills/jailbreak ~/.config/opencode/skills/
```

On Windows, copy the same folder with File Explorer or any file manager. The folder layout is identical on every OS.

## OpenCode

Copy `skills/jailbreak` into `~/.config/opencode/skills/` for a global install, or into the project `.opencode/skills/` folder. OpenCode also loads it when the repository is the working directory.

## Claude Code

Copy `skills/jailbreak` into `~/.claude/skills/` for a global install, or into the project `.claude/skills/` folder.

## Codex CLI

Codex reads `AGENTS.md`. Add this line to the project or global `AGENTS.md`:

```markdown
When adding a crack project to this repository, read `skills/jailbreak/SKILL.md` and follow it exactly.
```

If your Codex build supports a skills directory, copy `skills/jailbreak` there instead.

## Gemini CLI

Add this line to `GEMINI.md` in the repository root or `~/.gemini/GEMINI.md`:

```markdown
When adding a crack project to this repository, read `skills/jailbreak/SKILL.md` and follow it exactly.
```

## Cursor

Add an always-on rule:

```markdown
---
description: Add crack projects to the Jailbreak repository
globs: *
alwaysApply: true
---

When adding a crack project to this repository, read `skills/jailbreak/SKILL.md` and follow it exactly.
```

Save it as `.cursor/rules/jailbreak.mdc`.

## Windsurf

Create `.windsurf/rules/jailbreak.md` with the same pointer and set it to always on.

## Cline and Roo Code

Add the pointer to `.clinerules` or `.roorules`:

```markdown
When adding a crack project to this repository, read `skills/jailbreak/SKILL.md` and follow it exactly.
```

## Continue

Add a rule file:

```markdown
When adding a crack project to this repository, read `skills/jailbreak/SKILL.md` and follow it exactly.
```

Save it as `.continue/rules/jailbreak.md`.

## Aider

```bash
cp skills/jailbreak/SKILL.md CONVENTIONS.md
aider --read CONVENTIONS.md
```

Or add the pointer to an existing `CONVENTIONS.md`.

## Generic agent

If the harness has no skill system, load `skills/jailbreak/SKILL.md` as a rule or reference document. The workflow is plain Markdown. The scripts run anywhere with Node 16 or newer.

## Verify the install

Ask the agent:

```text
Add a new crack project for a test target under domains/system-utilities/example-target using the jailbreak skill.
```

The agent should read the skill, run `new-project.mjs`, and create `README.md` and `playbook.md` before doing any reverse engineering.
