# Ukrainian Fight Drone Simulator Playbook

Target: **Ukrainian Fight Drone Simulator Playtest**, Steam AppID `2862870`, Unreal Engine 5 Shipping, Windows x64.
Domain: `games`
Status: model verified on the reference build. This document is a methodology, not a payload.

This playbook teaches an agent how to take a UE5 Steam build that refuses to start without a Steam
client, find the exact decision that stops it, choose the right layer to replace or patch, and prove
the result offline. It does not contain a patched executable, a Steam emulator binary, a kit, or a
patcher script. The reference build values are evidence; a different build must be re-profiled with
section 4.

The short version: the game delay-loads `steam_api64.dll`, calls `SteamAPI_RestartAppIfNecessary`,
and exits when Steam is absent. There is no ownership check. Supply a local Steam API implementation,
and optionally remove the restart call with six bytes.

---

## 0. Contract

### 0.1 What "cracked" means here

The build is cracked when all of the following hold on a cold start with no Steam client installed,
no Steam account, and no network:

| Property | Evidence |
|---|---|
| The process starts and stays alive | `UFDS-Win64-Shipping.exe` alive after 30 s |
| The window renders | a game window titled `UFDS` exists and answers |
| The menu is reachable | ACADEMY / MULTIPLAYER / OPTIONS |
| A mission loads | mission 100 "ARM THE DRONE" reaches the cockpit |
| The simulation runs | HUD live, mission timer counting, controls respond |
| No Steam relaunch | no `steam://run/2862870//UFDS%20` handed to the shell |
| No licence server | no outbound request is required; the game works with all outbound traffic blocked |
| No telemetry | with the telemetry host blocked, zero outbound TCP connections during boot and menu |

A window that opens and closes, a menu screenshot, or "it did not crash" is not evidence. The
mission and the offline run are the gate.

### 0.2 The one rule

**Follow the failure, not the message.**

The first visible symptom is a Windows dialog: *"Get an app to open this 'steam' link"*. That dialog
is not the game's check; it is the shell handling a `steam://` URL emitted by Valve's DLL inside
`SteamAPI_RestartAppIfNecessary`. Patch or replace the decision, not the dialog. Likewise, an
emulator that makes `SteamAPI_Init` succeed is only half the job if the restart call still exits.

### 0.3 How an agent should use this document

1. **Profile.** Record the executable size and hash, the PE imports and delay imports, the AppID, the
   engine version, and the plugins compiled into the build.
2. **Reproduce the failure.** Run with no Steam client and capture the exit code, the log, and any
   URL handed to the shell. Do not start patching before the failure is understood.
3. **Locate the decision.** Section 4 walks the delay-import IAT to the call sites. Find the restart
   call and the init call on the target build.
4. **Choose the layer.** Section 5: a local Steam API provider for the interface layer, and a
   six-byte patch for the restart call if the build is to be made independent of the provider's
   behaviour.
5. **Verify offline.** Section 6, with a firewall block or an air-gapped run. A build that only works
   when it can reach the internet is not finished.
6. **Record the reference values.** Offsets, bytes and hashes belong in the playbook so the next
   agent can recognize the same build.
7. **Keep the rollback.** Section 7. A patch without a restore path is not a procedure.

Stop conditions: a different executable hash with a moved call site; a build that statically imports
`steam_api64.dll` instead of delay-loading it; an ownership or licence check that is not Steam
initialisation; a protected/packed executable; an anti-cheat that blocks the provider DLL.

### 0.4 What this document deliberately does not include

- No patched `UFDS-Win64-Shipping.exe`, no Steam emulator DLL, no loader, no patcher script.
- No key, account, ticket, or licence material.
- No pre-built `steam_settings` folder.

The agent obtains the Steam API provider from its upstream release, verifies its hash, and builds the
AppID/interface files from the target build. That is the difference between a playbook and a crack.

### 0.5 Scope

Use this on software you own or are authorised to modify. The target is a free Steam Playtest build;
the procedure removes a client dependency, it does not create a purchase entitlement.

---

## 1. Target profile

| Item | Value |
|---|---|
| Product | Ukrainian Fight Drone Simulator Playtest |
| Steam AppID | `2862870` |
| Build label | v1.6.2 / 255345, "Starter Edition", October 2026 |
| Engine | Unreal Engine 5, Shipping, Win64 |
| Main executable | `UFDS\Binaries\Win64\UFDS-Win64-Shipping.exe` (192,686,080 bytes) |
| Launcher | `UFDS.exe` (UE `BootstrapPackagedGame`, 249,856 bytes) |
| Steam integration | `SteamCorePro` plugin, compiled monolithically into the Shipping exe |
| Steam binding | **delay import** of `steam_api64.dll`, 14 functions |
| Other plugins | Sentry (crash/telemetry), JSBSim, SimpleController (SDL3), OpenCV, ONNX Runtime |
| Protection | none beyond Steam initialisation: no SteamStub, no Denuvo, no VMProtect, no licence server |
| Telemetry | Sentry native, DSN host in the startup log |
| Content | IoStore paks (`.ucas`/`.utoc`); no loose `.ini` config in the install; pak index is not plaintext |

Directory shape:

```text
Ukrainian Fight Drone Simulator\
  UFDS.exe
  UFDS\
    Binaries\Win64\UFDS-Win64-Shipping.exe
    Content\Paks\*.pak, *.ucas, *.utoc
    Plugins\SteamCorePro\Source\ThirdParty\SteamLibrary\redistributable_bin\win64\steam_api64.dll
    Plugins\Sentry\Binaries\Win64\crashpad_handler.exe
  Engine\...
```

The Valve `steam_api64.dll` is shipped inside the plugin source tree, but it is **not** next to the
executable in the reference install. That is why the delay-load fails before any Steam logic runs.

Steam delay imports, in IAT order:

```text
SteamAPI_RegisterCallback
SteamAPI_GetHSteamUser
SteamGameServer_RunCallbacks
SteamAPI_RunCallbacks
SteamInternal_GameServer_Init_V2
SteamAPI_UnregisterCallback
SteamInternal_SteamAPI_Init
SteamAPI_Shutdown
SteamInternal_FindOrCreateGameServerInterface
SteamInternal_FindOrCreateUserInterface
SteamInternal_ContextInit
SteamGameServer_Shutdown
SteamGameServer_GetHSteamUser
SteamAPI_RestartAppIfNecessary
```

---

## 2. Reference build

```text
UFDS-Win64-Shipping.exe
  size        192,686,080
  sha256      D5D5CCA3A410B4D602AD74F4D49BA210D7A93B45D8978394ECE278E257C35CE9
  image base  0x140000000
  entry RVA   0x82D5500
  sections    .text .rdata .data .pdata .msvcjmc CPADinfo .rodata _RDATA .rsrc .reloc
  flags       DYNAMICBASE, NX, high-entropy VA
  steam IAT   RVA 0x0AD72078 .. 0x0AD720E0 (file 0x0AD70E78 .. 0x0AD70EE0)
  restart     RVA 0x43968FC, file offset 0x4395EFC
```

AppID `2862870` appears in the `steam://run/2862870//UFDS%20` URL the Valve DLL hands to the shell.

The game's version string `v1.6.2/255345` is shown in the menu; use it together with the executable
hash to identify the build.

---

## 3. The model

### 3.1 Delay imports fail hard

`steam_api64.dll` is not in the static import table. The linker emitted delay-load thunks: the IAT
slots at `0x0AD72078` hold pointers to small stubs that call `__delayLoadHelper2`. On the first call,
the helper loads the DLL and resolves the function. If the DLL is missing, the helper raises; the
process dies before UE can write a log. On the reference build this is an instant exit code 1 with no
`Saved\Logs` file. That symptom is the delay-load failure, not a game check.

Consequence: removing `steam_api64.dll` cannot work. The build needs *some* implementation of the 14
functions.

### 3.2 The restart gate

`SteamAPI_RestartAppIfNecessary(2862870)` is called during SteamCore initialisation. With Valve's DLL
and no Steam client, the DLL hands the shell:

```text
steam://run/2862870//UFDS%20
```

and returns true. The game's branch calls the platform exit path at `0x139B1E0`, and the process ends. This is
the failure most users see as the "Get an app to open this 'steam' link" dialog.

The reference call site:

```text
RVA 0x43968FC   file 0x4395EFC
FF 15 DE B7 9D 06      call qword ptr [rip+0x69DB7DE]   ; IAT slot 0x0AD720E0
84 C0                  test al, al
0F 85 FB 01 00 00      jne  0x4396B05                     ; restart path -> RequestExit
```

A six-byte replacement makes the decision constant:

```text
31 C0 90 90 90 90      xor eax,eax ; nop x4              ; AL = 0, restart never required
```

That patch is independent of which `steam_api64.dll` is present. It is what makes the build survive
even if the provider DLL is later replaced by Valve's.

### 3.3 Steam initialisation

`SteamInternal_SteamAPI_Init` is called from the SteamCore subsystem:

```text
RVA 0x4375DB0   file 0x43753B0
FF 15 F2 C2 9F 06      call [IAT 0x0AD720A8]
85 C0                  test eax, eax
75 0A                  jne  skip-success-flag
```

A non-zero return means "init failed"; SteamCore does not set its logged-on flag and the rest of the
Steam interface layer is treated as unavailable. On the reference build this path is *tolerated*:
with Valve's DLL and no Steam, the game still reaches course selection and starts a mission, with
Steam features disabled.

### 3.4 The interface layer

SteamCore does not stop at init. It asks for interfaces by version string through
`SteamInternal_FindOrCreateUserInterface` and `SteamInternal_ContextInit`. The reference build asks
for these versions:

```text
STEAMAPPS_INTERFACE_VERSION008
STEAMHTMLSURFACE_INTERFACE_VERSION_005
STEAMHTTP_INTERFACE_VERSION003
STEAMMUSIC_INTERFACE_VERSION001
STEAMPARENTALSETTINGS_INTERFACE_VERSION001
STEAMREMOTEPLAY_INTERFACE_VERSION003
STEAMREMOTESTORAGE_INTERFACE_VERSION016
STEAMSCREENSHOTS_INTERFACE_VERSION003
STEAMUGC_INTERFACE_VERSION021
STEAMUSERSTATS_INTERFACE_VERSION013
SteamController008
SteamFriends018
SteamGameServer015
SteamGameServerStats001
SteamInput006
SteamMatchMaking009
SteamMatchMakingServers002
SteamNetworking006
SteamNetworkingSockets012
SteamNetworkingUtils004
SteamParties002
SteamUser023
SteamUtils010
```

A provider that does not serve a requested version returns null; a later call through that null
interface crashes. This is the reason the "stub everything" approach in 3.6 fails.

### 3.5 There is no ownership check

The build is a Playtest "Starter Edition". It contains no purchase gate, no entitlement query, no
licence server, and no DLC check that blocks play. The only gate is Steam initialisation plus the
restart call. Do not invent a licence patch; verify this on the target by running with a provider
that reports the app as owned and by checking the network traffic.

### 3.6 Two approaches that do not work

- **Delete `steam_api64.dll`.** Delay-load failure, instant exit, no log (3.1).
- **Stub the 14 imports to a zero-return gadget and force init failure.** The reference attempt
  patched all IAT slots to `xor eax,eax; ret`, forced both init calls to return failure, and removed
  the DLL. The build crashed with `EXCEPTION_ACCESS_VIOLATION reading 0x0000000000000000`: a caller
  dereferenced an interface pointer that the stub returned as null. A real interface implementation
  is required; the import table alone is not enough.

Valve's DLL *is* enough to boot (init fails gracefully), but it keeps the restart path and the
`steam://` relaunch unless the six-byte patch is applied, and it provides no offline achievements or
LAN layer.

### 3.7 Telemetry is not DRM

Sentry starts before the game and posts to
`o4508280536563712.ingest.us.sentry.io`. It is crash/log telemetry. It never blocks the game when the
network is down, but it is the only outbound dependency in the reference run. Block it if the target
must be quiet; do not mistake it for a licence check.

---

## 4. Discovery

Do this on the target build. Record every value in the sheet at 4.9.

### 4.1 Inventory

```text
dir /s /b "UFDS\Binaries\Win64\*.exe"
dir "UFDS\Binaries\Win64"
type "UFDS\Binaries\Win64\UFDS-Win64-Shipping.exe" >nul
```

Record: executable size, `UFDS.exe` presence, the plugin folders, the pak layout, and whether
`steam_api64.dll` sits next to the executable. In the reference install it does not.

### 4.2 Imports and delay imports

Use `pefile` (or any PE viewer) and print both tables. The delay-import descriptor for
`steam_api64.dll` gives the IAT RVA, the module handle slot, and the 14 names. Record the IAT range.

```python
import pefile
pe = pefile.PE(path, fast_load=True)
pe.parse_data_directories(directories=[
    pefile.DIRECTORY_ENTRY['IMAGE_DIRECTORY_ENTRY_IMPORT'],
    pefile.DIRECTORY_ENTRY['IMAGE_DIRECTORY_ENTRY_DELAY_IMPORT']])
for e in pe.DIRECTORY_ENTRY_DELAY_IMPORT:
    print(e.dll.decode(), [(i.name or i.ordinal, hex(i.address)) for i in e.imports])
```

If `steam_api64.dll` is a static import instead, the model changes: the loader fails before the
process starts, and the provider DLL must be present at launch. The patch work is the same; the
failure symptom is different.

### 4.3 Find the restart call

1. Take the IAT slot for `SteamAPI_RestartAppIfNecessary`.
2. Scan `.text` for `call qword ptr [rip+disp]` and `jmp qword ptr [rip+disp]` whose target is that
   slot. The reference build has exactly one call.
3. Disassemble around it. Look for `test al,al` followed by a conditional jump to a block that calls
   `RequestExit` or ends the subsystem.
4. Record the call RVA, file offset, and the branch target. Verify the branch really exits: follow
   the target and look for the platform exit call, not just a return.

A working scanner for the delay-import IAT and its call sites:

```python
import pefile, struct

P = r"UFDS\Binaries\Win64\UFDS-Win64-Shipping.exe"
pe = pefile.PE(P, fast_load=True)
pe.parse_data_directories(directories=[pefile.DIRECTORY_ENTRY["IMAGE_DIRECTORY_ENTRY_DELAY_IMPORT"]])
base = pe.OPTIONAL_HEADER.ImageBase
text = [s for s in pe.sections if s.Name.rstrip(b"\0") == b".text"][0]
code = open(P, "rb").read()[text.PointerToRawData:text.PointerToRawData + text.SizeOfRawData]

slots = {}
for e in pe.DIRECTORY_ENTRY_DELAY_IMPORT:
    if b"steam" in e.dll.lower():
        for i in e.imports:
            slots[i.address - base] = i.name.decode()

for i in range(len(code) - 6):
    if code[i] == 0xFF and code[i + 1] in (0x15, 0x25):
        disp = struct.unpack_from("<i", code, i + 2)[0]
        rva = text.VirtualAddress + i
        tgt = rva + 6 + disp
        if tgt in slots:
            print("%-45s call/jmp at RVA %08X file %08X" % (slots[tgt], rva, text.PointerToRawData + i))
```

On the reference build this prints one call for `SteamAPI_RestartAppIfNecessary` at RVA `0x43968FC`
and one for `SteamInternal_SteamAPI_Init` at RVA `0x4375DB0`.

### 4.4 Find the init call

Repeat for `SteamInternal_SteamAPI_Init`. The reference build has one call, followed by
`test eax,eax` and a branch that skips the "logged on" flag on failure. Record it; it tells you
whether the build tolerates init failure or aborts.

Also locate `SteamInternal_GameServer_Init_V2`; listen-server builds may call it from a separate
path.

### 4.5 Interface versions

SteamCore stores the version strings as narrow ASCII in `.rdata` near the interface getters. Extract
every `Steam*[0-9]{3}` and `STEAM*_INTERFACE_VERSION*` string. The list in 3.4 is the reference
build's set; a new build may add or bump versions.

### 4.6 AppID and the steam:// URL

The AppID is the number in the URL the Valve DLL hands to the shell. Capture it without Steam:

1. Register a temporary `HKCU\Software\Classes\steam\shell\open\command` handler that appends `%1`
   to a log file.
2. Run the game with the Valve DLL present and no Steam client.
3. Read the URL. On the reference build: `steam://run/2862870//UFDS%20`.
4. Remove the handler.

The AppID is also visible in the store page URL and in any Steam shortcut, but the URL capture proves
which id the build actually asks for.

### 4.7 Telemetry host

Run the build with `-log -stdout -FullStdOutLogOutput` and read the Sentry lines, or watch
`Get-NetTCPConnection -OwningProcess <pid>` during boot. The reference build posts to
`o4508280536563712.ingest.us.sentry.io:443`. The DSN host is the block target.

### 4.8 Configuration and paks

The content is in IoStore (`.ucas`/`.utoc`); the index is not plaintext and a string scan of the `.pak` finds
nothing. Do not plan on editing an `.ini` inside the pak. The telemetry override attempt through
`%LOCALAPPDATA%\UFDS\Saved\Config\Windows\Engine.ini` was deleted at startup and had no effect.

### 4.9 Discovery sheet

| Field | Target value |
|---|---|
| Executable size + SHA-256 | |
| Build label | |
| AppID | |
| `steam_api64.dll` static or delay | |
| IAT range | |
| Restart call RVA / file offset / bytes | |
| Restart branch target | |
| Init call RVA / failure branch | |
| Requested interface versions | |
| Telemetry host | |
| Provider DLL version/hash chosen | |

---

## 5. Solution

### 5.1 Choose the interface provider

The provider must implement the 14 exported functions and the Steam interfaces the build requests.
The reference used **gbe_fork** (Goldberg Steam Emulator fork), tag `release-2026_09_27`, x64
`steam_api64.dll`, SHA-256
`70D9826A402D3A78B0C07E9F7EA7C6832468A1113013F31EA570FCCAA5445EA9`.

Requirements for any provider:

- Exports all 14 names from the delay-import table.
- `SteamAPI_RestartAppIfNecessary` returns false.
- `SteamInternal_SteamAPI_Init` returns success (`0`).
- Serves `SteamInternal_FindOrCreateUserInterface` for every version in 4.5 and returns non-null
  interface objects.
- Implements `SteamInternal_ContextInit` with the SDK's caching semantics.
- Reports AppID `2862870` as owned and logged on.

Do not use a random "steam_api64.dll" from a download site. Verify the release hash and source.

### 5.2 Install the provider

1. Put the provider DLL at `UFDS\Binaries\Win64\steam_api64.dll`.
2. Write `steam_appid.txt` containing `2862870` in the game root and next to the executable. The
   provider reads it for the current app id.
3. Create `UFDS\Binaries\Win64\steam_settings\` with:
   - `steam_appid.txt` - `2862870`
   - `account_name.txt`, `language.txt`
   - `steam_interfaces.txt` - the exact versions from 4.5, one per line
4. Keep the Valve DLL that ships in `UFDS\Plugins\SteamCorePro\Source\ThirdParty\...` as the
   original reference; do not overwrite it.

The interface list matters. If the provider uses a built-in default list that lacks a version the
game asks for, the getter returns null and the game crashes later, usually on a menu that touches
friends, stats or networking.

### 5.3 Patch the restart call (optional, recommended)

If the build must keep working regardless of the provider's restart behaviour, apply the six-byte
patch from 3.2:

```text
file offset 0x4395EFC
before  FF 15 DE B7 9D 06
after   31 C0 90 90 90 90
```

Rules:

- Verify the six bytes before writing. If they differ, the build has changed; re-run 4.3.
- Recalculate the PE checksum if the build is inspected by a tool that cares. Windows does not
  require it for user executables, but a stale checksum is a fingerprint.
- Do not patch `SteamInternal_SteamAPI_Init` to failure when a provider is present; let the provider
  answer. Forcing failure is what produced the null-interface crash in 3.6.
- Record the patched hash. Reference patched hash:
  `913C71DA5E549F2F51FAD01A5323F8E92CA7FECDB4037EBC3C0159E9A2BFC242`.

### 5.4 Quiet the telemetry (optional)

Add to the Windows `hosts` file:

```text
0.0.0.0 o4508280536563712.ingest.us.sentry.io
```

Flush DNS. This is a telemetry endpoint, not a licence server. If the target must run with no
network at all, a firewall outbound block on both `UFDS.exe` and `UFDS-Win64-Shipping.exe` is the
stronger test; the game must pass with it.

### 5.5 Order and failure handling

1. Provider DLL + AppID + settings.
2. Launch, no Steam. If it exits instantly with code 1 and no log, the provider is missing or a
   delay-load still fails. If it shows the `steam://` dialog, the restart call was reached; apply
   the patch or fix the provider's restart return.
3. Patch the restart call only after the provider path works, so a failure is attributable.
4. Verify offline (section 6) before calling it done.

### 5.6 What not to do

- Do not delete the provider DLL to "remove Steam"; the delay import needs it.
- Do not stub the imports to a single zero-return gadget (3.6).
- Do not patch init to failure while expecting interfaces to work (3.6).
- Do not edit paks or `Engine.ini` for telemetry; the config is deleted/ignored at startup.
- Do not add a licence patch; there is no licence check to defeat.

---

## 6. Verification

### 6.1 Static

- Provider DLL present and hash matches the release.
- `steam_appid.txt` = `2862870` in both locations.
- `steam_settings\steam_interfaces.txt` contains every version from 4.5.
- If patched: six bytes at `0x4395EFC` read `31 C0 90 90 90 90`.

### 6.2 Dynamic, no Steam

Launch `UFDS.exe` with no Steam client installed. Confirm:

- `UFDS-Win64-Shipping.exe` alive after 30 s.
- Window `UFDS` exists.
- No `steam://run/2862870//UFDS%20` in the shell handler log.
- No crash reporter window.

### 6.3 Offline

Block outbound traffic for both executables (firewall or air-gap), launch again, and confirm the same
state. With the hosts block, `Get-NetTCPConnection -OwningProcess <pid>` should show zero non-local
connections during boot and menu.

### 6.4 Gameplay

Enter the ACADEMY tab, open mission 100 "ARM THE DRONE", continue to the cockpit. Confirm the HUD is
live, the mission timer counts, and controls respond. This is the only proof that the interface layer
and the initialisation path are both healthy.

### 6.5 Negative checks

- No Steam client process is required.
- No account, ticket, or purchase prompt.
- No outbound connection is required for the menu or the mission.
- No `Sentry` envelope leaves the machine when the host is blocked.

---

## 7. Rollback

- **Executable:** restore the six bytes at `0x4395EFC` to `FF 15 DE B7 9D 06`, then fix the PE
  checksum. Original hash:
  `D5D5CCA3A410B4D602AD74F4D49BA210D7A93B45D8978394ECE278E257C35CE9`.
- **Provider:** delete `UFDS\Binaries\Win64\steam_api64.dll`, `steam_appid.txt` (both locations),
  and `steam_settings\`. The original Valve DLL is still in the plugin source tree:
  `UFDS\Plugins\SteamCorePro\Source\ThirdParty\SteamLibrary\redistributable_bin\win64\steam_api64.dll`.
- **Telemetry:** remove the hosts line and flush DNS.
- Restore any firewall rules added for the offline test.

A build that cannot be rolled back is not a finished procedure.

---

## 8. Drift and new builds

| Change | Effect | Action |
|---|---|---|
| Game update, same engine | restart/init call sites may move | re-run 4.3/4.4; the pattern is the delay-import xref |
| Steamworks SDK bump | new interface versions | re-run 4.5; regenerate the provider's interface list |
| New provider release | ABI/SDK support changes | verify exports and hash; re-test 6.4 |
| UE upgrade | delay-load layout may change | re-profile; check whether the import becomes static |
| AppID change | provider reports the wrong app | capture the new `steam://` URL (4.6) |
| Anti-cheat added | provider may be blocked | stop; this model does not cover a protected build |

Re-profiling checklist:

1. Executable hash and build label.
2. Static vs delay import of `steam_api64.dll`.
3. IAT slots and all 14 names.
4. Restart call xref and branch target.
5. Init call and failure path.
6. Interface versions from strings.
7. AppID from the URL capture.
8. Telemetry host from the log or a connection watch.
9. Provider release that supports the SDK level.

When to stop: the build statically links Steam and the loader fails before the game starts; the
executable is packed/protected; the game adds an ownership check outside Steam; the provider cannot
serve a required interface and the null dereference is unavoidable.

---

## 9. Pitfalls

- **Exit code 1 with no log is a delay-load failure**, not a game decision. Check that
  `steam_api64.dll` sits next to the executable before hunting for checks.
- **The `steam://` dialog is emitted by Valve's DLL**, not by the game UI. Capture the URL to learn
  the AppID, then patch the call or use a provider that returns false.
- **`SteamAPI_RestartAppIfNecessary` returns true -> RequestExit.** The branch is not a log line; it
  ends the process.
- **A provider that only implements init is not enough.** Interface getters run 1,500+ times; every
  requested version must return a real object.
- **Stubbing all imports to `xor eax,eax; ret` crashes** on the first null interface dereference.
- **Forcing init failure while a provider is present** produces the same null-interface crash.
- **The `.pak` index is not plaintext**; do not plan on editing config inside it.
- **`Saved\Config\Windows\Engine.ini` is deleted at startup**; it cannot disable Sentry.
- **The game is a Playtest "Starter Edition"** with a personal-use disclaimer; there is no trial
  timer or purchase gate to patch.
- **Steam features are local only** with the provider: achievements and cloud saves go to the
  provider's store, multiplayer is LAN; Steam public matchmaking is unavailable.
- **Keep the patch minimal.** Six bytes on one call is enough; every additional byte is a new failure
  surface.

---

## 10. Acceptance checklist

```text
[ ] Build identified: executable hash + label + AppID
[ ] Delay imports enumerated; provider exports all 14
[ ] Restart call found; branch confirmed to exit
[ ] Init call found; failure behavior understood
[ ] Interface versions extracted and served by the provider
[ ] steam_appid.txt in both locations
[ ] steam_settings\steam_interfaces.txt matches the build
[ ] Optional six-byte patch applied at the restart call, bytes verified
[ ] No Steam client, no network: process alive, window renders
[ ] Menu reached: ACADEMY / MULTIPLAYER / OPTIONS
[ ] Mission 100 loads; HUD, timer and controls live
[ ] Zero outbound connections with the telemetry block
[ ] Rollback bytes and files documented
```


