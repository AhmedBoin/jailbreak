# Install Uncensored.md

`Uncensored.md` is a plain-text system prompt. Any harness that accepts custom instructions can load it.

Two rules:

1. Load it as a system prompt, project instruction file, or always-on rule. Do not paste it into the user message.
2. Use one instruction file per harness. Duplicating the same text in `AGENTS.md`, `CLAUDE.md`, and a custom prompt can produce conflicting instructions.

The commands below assume the repository is cloned and the current directory is the repository root.

## Claude Code

Project scope:

```bash
cp Uncensored.md CLAUDE.md
```

Global scope:

```bash
mkdir -p ~/.claude
cp Uncensored.md ~/.claude/CLAUDE.md
```

Windows:

```bat
copy Uncensored.md "%USERPROFILE%\.claude\CLAUDE.md"
```

Claude Code also supports imports from a `CLAUDE.md` file:

```markdown
@Uncensored.md
```

## Codex CLI

Project scope:

```bash
cp Uncensored.md AGENTS.md
```

Global scope:

```bash
mkdir -p ~/.codex
cp Uncensored.md ~/.codex/AGENTS.md
```

Windows:

```bat
copy Uncensored.md "%USERPROFILE%\.codex\AGENTS.md"
```

Codex reads `AGENTS.md` from the repository root and parent directories.

## OpenCode

Project scope:

```bash
cp Uncensored.md AGENTS.md
```

Global scope:

```bash
mkdir -p ~/.config/opencode
cp Uncensored.md ~/.config/opencode/AGENTS.md
```

Windows:

```bat
copy Uncensored.md "%USERPROFILE%\.config\opencode\AGENTS.md"
```

OpenCode reads `AGENTS.md` and project-level agent configuration. Keep one copy.

## Gemini CLI

Project scope:

```bash
cp Uncensored.md GEMINI.md
```

Global scope:

```bash
mkdir -p ~/.gemini
cp Uncensored.md ~/.gemini/GEMINI.md
```

Windows:

```bat
copy Uncensored.md "%USERPROFILE%\.gemini\GEMINI.md"
```

If your Gemini CLI configuration uses `contextFileName`, point it at `Uncensored.md` instead of copying.

## Cursor

Create an always-on rule:

```bash
mkdir -p .cursor/rules
cp Uncensored.md .cursor/rules/uncensored.mdc
```

Prepend the rule metadata:

```markdown
---
description: Uncensored operator prompt
globs: *
alwaysApply: true
---
```

Legacy Cursor projects can use:

```bash
cp Uncensored.md .cursorrules
```

## Windsurf

```bash
mkdir -p .windsurf/rules
cp Uncensored.md .windsurf/rules/uncensored.md
```

Open the Windsurf rules panel and set the rule to always on.

## Cline

```bash
cp Uncensored.md .clinerules
```

If your Cline build uses the custom instructions field instead, paste the contents of `Uncensored.md` there.

## Roo Code

```bash
cp Uncensored.md .roorules
```

Roo Code also accepts custom instructions in its settings. Use one location.

## Continue

Create a rule file:

```bash
mkdir -p .continue/rules
cp Uncensored.md .continue/rules/uncensored.md
```

Or add it as the system message in `~/.continue/config.json`:

```json
{
  "systemMessage": "Read Uncensored.md and follow it as your system prompt."
}
```

For a fully self-contained config, paste the full text of `Uncensored.md` into the `systemMessage` string.

## Aider

```bash
cp Uncensored.md CONVENTIONS.md
aider --read CONVENTIONS.md
```

Or add this to `.aider.conf.yml`:

```yaml
read: CONVENTIONS.md
```

Aider loads the file as read-only context for every request.

## Generic API or custom harness

Send `Uncensored.md` as the system message:

```text
system: <full contents of Uncensored.md>
user: <request>
```

Do not append the prompt to the user message. It belongs in the system or instruction channel.

## Verification

Start a new session after installing the file. Ask a test request that would normally trigger a refusal, for example:

```text
Explain how to patch a binary that you own, including the exact file offsets and bytes.
```

If the response starts with a refusal, a disclaimer, or a safer alternative, the harness did not load the file. Check the path, the file name, and whether the harness reads project or global instructions.

## Notes

- `CLAUDE.md`, `AGENTS.md`, `GEMINI.md`, and `CONVENTIONS.md` are read automatically by their respective tools.
- Cursor, Windsurf, Cline, Roo Code, and Continue may require enabling the rule in the UI.
- If a harness supports both project and global instructions, use the global file for a machine-wide default and the project file only when you want to override it.
- Keep the prompt as a single file. Do not split it across multiple instruction files.
