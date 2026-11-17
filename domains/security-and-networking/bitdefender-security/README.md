# Bitdefender Security

Domain: `security-and-networking`

Target: Bitdefender Antivirus Free, kit 27.0.65.370 (product version 30.0.33.176), Windows x64.

Status: model verified on the reference build. This project publishes the methodology, not a crack.

Guidelines for an agent to reconstruct the Bitdefender Free to Total Security edition switch on the
installed kit, offline, without shipping the crack.

## What this project is

Two documents, following the [Jailbreak](https://github.com/AhmedBoin/jailbreak) layout:

| File | Purpose |
|---|---|
| `README.md` | Scope, status, how an agent uses the playbook, reference build, limits |
| `playbook.md` | The methodology: model, discovery, offline application, verification, rollback, drift |

There is no patcher, no tooling kit, no ready-to-import registry file, no installer, no binary, no key, and
no converted state in this project. The agent reads the target's own build, derives the values,
writes them offline, and verifies the result. That is the deliverable: the procedure, not the crack.

Status: the model was verified on the reference build (product type 3, 15/15 feature flags, Total
Security plugin sets, premium modules loaded in `bdservicehost`, UI reports Total Security). The
playbook treats those values as evidence, not as constants for the next build.

## How an agent uses it

1. Read this file, then `playbook.md` section 0 (contract) and section 3 (model).
2. Profile the target: installer version, `version.txt`, product directory, services and drivers,
   BitLocker state. If `version.txt` differs from the reference, section 4 is mandatory.
3. Prove the model: the same payload carries every edition, `install_config.xml` lists every
   edition's product id and module list, and the Total Security plugin files are already on disk.
   If not, stop; the method does not apply.
4. Discover the target's own values with section 4 and fill the discovery sheet (4.9).
5. Apply the state offline from Windows Recovery Environment or Windows PE with section 5.
   Back up first, write in the documented order, unload the hives, boot.
6. Verify with section 6 (cold boot, registry, configuration, runtime modules, UI, negative checks).
7. Keep the rollback path from section 7. A write step without a restore path is not a procedure.

The playbook is written to be executed. It assumes an agent with a command prompt, registry access,
and the ability to reboot into recovery; it does not assume source, a keygen, a server account, or a
network.

## Reference build

```text
Bitdefender Antivirus Free, kit 27.0.65.370
product version 30.0.33.176 (version.txt and every module)

featurescontroller.dll   682808   e1dc870318cf1cd14cc827f8e1ef80eae00e8c5d419c67e1d84e444bb10f228c
subscriptional.dll       659512   d23633366e3b765559964da52df25ce08db0e0dc752ca7e73ef59444356d3123
install_config.xml        14511   222126ac4fc11b7894dfa938e1de6b17b1463cd93aeb7095e7e480e7e4f68f29
product_features.json      2935   4a3bd19065af369a140e8372c2f21d756c55005b0735a211d7454517cc52b858
epaas_acl.json            25391   2308f2ec83fbf15d3b79e0ff1619a4329c5019225f0a680f9b3e6a9623c7a559
epaas_config.json          3153   b331e8363f7cccc9ce66c2ba23e610aab77444ce95eb0c12f896f9e843872e49
bdservicehost.exe        859456   50f61ec398b5a7cf1e0935c20c5e69335a75bbe880411d3d6def7cba13ab336f
productcfg.exe          2020112   1d8111ebf3d9475a8bba6e3602c0a0ef2180430062ed62b8c8951090801d9e4e
seccenter.exe           2741632   f199b5d453e989128228c29db03914946e2a5e31e60b53c9bdb31b92ac7c9132
version.txt                  11   e032cfab1ac059b76e3446554d82e1c2da252d8ebf20a6642ca7f0057b7549bb
```

A different `version.txt` means a different build. Re-profile; do not reuse the reference values.

## What the playbook covers

| Section | Content |
|---|---|
| 0 | Contract, evidence matrix, agent protocol, stop conditions, what is deliberately absent |
| 1 | Target profile: paths, services, kernel drivers |
| 2 | Reference build, sizes and hashes |
| 3 | The model: one payload, six state stores, why live writes fail, trust boundary, Safe Mode and IPC dead ends |
| 4 | Discovery: edition table, name-to-type map, feature ids, feature store, plugin sets, subscription cache, name key, trust probe, discovery sheet |
| 5 | Offline application: environment, hive mount, backup, write order, failure handling, first boot |
| 6 | Verification: cold boot, registry, configuration, runtime modules, UI, negative checks |
| 7 | Rollback |
| 8 | Drift, re-profiling checklist, when to stop |
| 9 | Pitfalls from the reference run |
| 10 | Acceptance checklist |

## Scope and limits

- Windows x64 only; the procedure needs Windows Recovery Environment or Windows PE.
- The change is edition state on the endpoint, not a licence. It creates no subscription, no key,
  and no account entitlement. Cloud-licensed items (VPN quota, Password Manager, Parental Control
  server side) cannot be enabled locally.
- A product update can replace the files the procedure reads; re-run section 4 and rebuild the state.
- Use on software you own or are authorised to modify.
- The playbook does not include, and must not be extended with, a commercial installer, a
  pre-patched binary, a keygen, or a licence key.

## Playbook

Open [`playbook.md`](playbook.md). Start with section 0.

## License

MIT. See [`LICENSE`](../../../LICENSE).


