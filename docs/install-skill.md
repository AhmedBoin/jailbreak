# Install the add-crack skill

The canonical skill is:

```text
skills/add-crack/
  SKILL.md
  references/
    playbook-template.md
    patcher-checklist.md
    project-readme-template.md
  scripts/
    new-project.ps1
    check-repo.ps1
```

The repository also ships thin wrappers for OpenCode and Claude Code:

```text
.opencode/skills/add-crack/SKILL.md
.claude/skills/add-crack/SKILL.md
```

Each wrapper points at the canonical `skills/add-crack/SKILL.md`.

## OpenCode

The repository wrapper is already in place. OpenCode loads it when the repository is the working directory.

For a global install:

```bash
mkdir -p ~/.config/opencode/skills
cp -r skills/add-crack ~/.config/opencode/skills/
```

Windows:

```bat
xcopy /E /I skills\add-crack "%USERPROFILE%\.config\opencode\skills\add-crack"
```

## Claude Code

The repository wrapper is already in place. For a global install:

```bash
mkdir -p ~/.claude/skills
cp -r skills/add-crack ~/.claude/skills/
```

Windows:

```bat
xcopy /E /I skills\add-crack "%USERPROFILE%\.claude\skills\add-crack"
```

## Codex CLI

Codex reads `AGENTS.md`. Add this line to the project or global `AGENTS.md`:

```markdown
When adding a crack project to this repository, read `skills/add-crack/SKILL.md` and follow it exactly.
```

If your Codex build supports a skills directory, copy `skills/add-crack` there instead.

## Gemini CLI

Add this line to `GEMINI.md` in the repository root or `~/.gemini/GEMINI.md`:

```markdown
When adding a crack project to this repository, read `skills/add-crack/SKILL.md` and follow it exactly.
```

## Cursor

Add an always-on rule:

```markdown
---
description: Add crack projects to the Jailbreak repository
globs: *
alwaysApply: true
---

When adding a crack project to this repository, read `skills/add-crack/SKILL.md` and follow it exactly.
```

Save it as `.cursor/rules/add-crack.mdc`.

## Windsurf

Create `.windsurf/rules/add-crack.md` with the same pointer and set it to always on.

## Cline and Roo Code

Add the pointer to `.clinerules` or `.roorules`:

```markdown
When adding a crack project to this repository, read `skills/add-crack/SKILL.md` and follow it exactly.
```

## Continue

Add a rule file:

```markdown
When adding a crack project to this repository, read `skills/add-crack/SKILL.md` and follow it exactly.
```

Save it as `.continue/rules/add-crack.md`.

## Aider

```bash
cp skills/add-crack/SKILL.md CONVENTIONS.md
aider --read CONVENTIONS.md
```

Or add the pointer to an existing `CONVENTIONS.md`.

## Generic agent

If the harness has no skill system, load `skills/add-crack/SKILL.md` as a rule or reference document. The workflow is plain Markdown and the scripts are plain PowerShell.

## Verify the install

Ask the agent:

```text
Add a new crack project for a test target under domains/system-utilities/example-target using the add-crack skill.
```

The agent should read the skill, run `new-project.ps1`, and create `README.md` and `playbook.md` before doing any reverse engineering.
