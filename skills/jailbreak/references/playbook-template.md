# {{TITLE}} Playbook

Target: {{TITLE}}
Version: {{VERSION}}
Domain: {{DOMAIN}}
Status: draft

## 1. Target profile

- Vendor:
- Install path:
- Main executable:
- Main code module:
- Architecture:
- Framework:
- Packer or protector:
- License UI:
- Update mechanism:
- Secondary environment, if any:

## 2. Reference build

```text
file
size
sha256
image base
sections, load commands, or program headers
```

Record the exact build used for the offsets below. A patcher must refuse any other build.

## 3. Protection analysis

Explain the license flow:

- Which module constructs the license manager.
- Which checker class is used.
- How the checker is selected for desktop, boot media, or portable mode.
- What `IsRegistered` returns and what data it reads.
- What `GetLicenseType` returns and which edition values exist.
- Where the license data comes from, if any.
- Whether the target verifies signatures or file hashes.

## 4. Patch sites

| Checker | Method | RVA | File offset | Original bytes | Patch |
|---|---|---|---:|---|---|
|  | `IsRegistered` |  |  |  | `B0 01 C3` |
|  | `GetLicenseType` |  |  |  | `B8 08 00 00 00 C3` |

Explain each patch and the edition value used. The example bytes are x86 and x64. For ARM64, record the equivalent return stub for the target architecture.

## 5. Finding the sites in a new version

Document at least one reliable discovery path:

- RTTI names and vtable symbols.
- Strings and xrefs.
- Class names and factory function.
- Edition switch table.
- Error dialog text.
- Signature scan or byte pattern.

Include commands and small scripts. Another engineer must be able to find the same functions in a new build.

## 6. Verification

Desktop:

- Title bar or About dialog:
- Previously gated feature:
- Register or upgrade prompt:
- Patcher hash after apply:

Secondary environment:

- Boot media or portable mode:
- Registration error:
- Edition shown:
- Rebuild command:

## 7. Rollback

- Pristine backup location:
- Pristine SHA256:
- Restore steps:

## 8. Packaging and secondary media

- How the product builds secondary media, if applicable: WinPE, recovery image, or live image.
- Where the patched module must be embedded.
- ISO or image rebuild command.
- Boot files and catalog details.
- Files that must be removed before packaging.

## 9. Notes

Known limitations, update behavior, and anything a future engineer should check first.
