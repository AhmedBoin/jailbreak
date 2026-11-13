# {{TITLE}}

Domain: `{{DOMAIN}}`

Target: {{TITLE}} {{VERSION}}

Status: draft

{{SUMMARY}}

## Files

| File | Purpose |
|---|---|
| `playbook.md` | Full analysis, offsets, discovery workflow, verification, and rollback |
| `patcher/` | Optional standalone patcher and source |
| `legacy/` | Optional old scripts or notes |

## Quick start

1. Close the target application.
2. Run the patcher from `patcher/` with the rights the target requires.
3. Click `Check`, then `Apply`.
4. Rebuild any boot media or secondary environment with the patched files.
5. Verify the title bar or About dialog shows the expected edition.

## Reference build

```text
size
sha256
```

## Verification

- Desktop:
- Secondary environment:
- Patcher hash after apply:

## Updates

Describe what an update replaces and whether the patcher must be rebuilt.

## Playbook

Open [`playbook.md`](playbook.md).

## License

MIT. See the repository [`LICENSE`](../../../LICENSE).
