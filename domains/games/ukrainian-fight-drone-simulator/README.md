# Ukrainian Fight Drone Simulator

Domain: `games`

Target: Ukrainian Fight Drone Simulator Playtest, Steam AppID `2862870`, Unreal Engine 5 Shipping, Windows x64.

Status: model verified on the reference build. This project publishes the methodology, not a crack.

Guidelines for an agent to make Ukrainian Fight Drone Simulator run offline without Steam, by
finding the decision that stops it and supplying the Steam layer it expects.

## What this project is

Two documents, following the [Jailbreak](https://github.com/AhmedBoin/jailbreak) layout:

| File | Purpose |
|---|---|
| `README.md` | Scope, status, how an agent uses the playbook, reference build, limits |
| `playbook.md` | The methodology: model, discovery, patch sites, provider setup, verification, rollback, drift |

There is no patched executable, no Steam emulator DLL, no kit, no patcher script, and no pre-built
`steam_settings` folder in this project. The agent profiles the target, finds the delay-import
call sites, obtains a Steam API provider, and verifies the result offline. That is the deliverable:
the procedure, not the crack.

Status: the model was verified on the reference build. With a local Steam API provider and no Steam
client, the game reached the ACADEMY menu, the MULTIPLAYER screen, mission 100 details, and the drone
cockpit with a live HUD and running mission timer, with all outbound traffic blocked. A six-byte
patch on the restart call was also verified to make the executable independent of Valve's restart
behaviour.

## How an agent uses it

1. Read this file, then `playbook.md` section 0 (contract) and section 3 (model).
2. Reproduce the failure on the target: no Steam client, capture the exit code, the log, and any
   `steam://` URL handed to the shell.
3. Inventory the executable: size, hash, PE imports, and the `steam_api64.dll` delay-import table.
4. Find the restart and init call sites with section 4. Record the RVA, file offset, and bytes.
5. Extract the requested Steam interface versions and the AppID.
6. Install a Steam API provider that exports all 14 delay imports and serves every requested
   interface version; add the AppID and interface files (section 5).
7. Optionally apply the six-byte restart patch, then verify offline (section 6).
8. Keep the rollback bytes and files from section 7.

The playbook is written to be executed. It assumes an agent with a PE viewer, a hex editor, a
command prompt, and the ability to run the game; it does not assume source, a keygen, a Steam
account, or a network.

## Reference build

```text
Ukrainian Fight Drone Simulator Playtest
Steam AppID 2862870
UE5 Shipping, v1.6.2 / 255345 ("Starter Edition", October 2026)

UFDS-Win64-Shipping.exe
  size      192,686,080
  sha256    D5D5CCA3A410B4D602AD74F4D49BA210D7A93B45D8978394ECE278E257C35CE9   (original)
  913C71DA5E549F2F51FAD01A5323F8E92CA7FECDB4037EBC3C0159E9A2BFC242             (restart call patched)

restart call   RVA 0x43968FC   file 0x4395EFC
before         FF 15 DE B7 9D 06   call [SteamAPI_RestartAppIfNecessary]
after          31 C0 90 90 90 90   xor eax,eax ; nop x4

provider       gbe_fork tag release-2026_09_27, x64 steam_api64.dll
sha256         70D9826A402D3A78B0C07E9F7EA7C6832468A1113013F31EA570FCCAA5445EA9
```

A different executable hash means a different build. Re-run the discovery steps; do not reuse the
offset.

## What the playbook covers

| Section | Content |
|---|---|
| 0 | Contract, evidence matrix, agent protocol, stop conditions, what is deliberately absent |
| 1 | Target profile: engine, plugins, delay imports, directory shape |
| 2 | Reference build: hashes, IAT range, call site |
| 3 | The model: delay-load failure, restart gate, init path, interface layer, why stubs and DLL deletion fail, telemetry is not DRM |
| 4 | Discovery: imports, restart xref, init xref, interface versions, AppID capture, telemetry host, encrypted paks, discovery sheet |
| 5 | Solution: provider requirements, install order, six-byte patch, telemetry block, what not to do |
| 6 | Verification: static, no-Steam boot, offline run, mission, negative checks |
| 7 | Rollback: bytes, files, Valve DLL source |
| 8 | Drift, re-profiling checklist, when to stop |
| 9 | Pitfalls from the reference run |
| 10 | Acceptance checklist |

## Scope and limits

- Windows x64, UE5 Shipping build. The procedure targets a delay-loaded Steam API, not a protected
  or statically linked one.
- The target is a free Playtest build. The procedure removes a Steam-client dependency; it does not
  create a purchase entitlement or a licence.
- Achievements and cloud saves are local to the provider; multiplayer is LAN only. Steam public
  matchmaking is not available.
- A game update can move the call sites or change the interface versions; re-run section 4 and
  regenerate the provider's interface list.
- Use on software you own or are authorised to modify.
- The playbook does not include, and must not be extended with, a pre-patched executable, a provider
  binary, a keygen, or licence material.

## Playbook

Open [`playbook.md`](playbook.md). Start with section 0.

## License

MIT. See [`LICENSE`](../../../LICENSE).



