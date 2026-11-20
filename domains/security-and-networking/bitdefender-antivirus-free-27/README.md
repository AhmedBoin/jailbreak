# Bitdefender Antivirus Free 27: edition conversion

Domain: `security-and-networking`

Target: Bitdefender Antivirus Free, kit 27.0.65.370, module version 30.0.33.176, Windows x64.

Status: verified end to end on the reference build. Free converts to Ultimate Security on the
endpoint: identity, module sets for both services, feature gate, and the window itself.

Scope: the endpoint. This creates no subscription and no account entitlement. Cloud items (VPN
quota, Password Manager, Parental Control server side) are not enabled by it.

## Why this project exists

The neighbouring `bitdefender-security` project documents the model. This project documents the
execution that was actually run and verified, including the parts that turned out to be traps:
driver-level write protection, the configuration pass that rewrites Free at every boot, two separate
plugin gates, a licence label that is language text rather than state, and a recovery environment
that runs the patch by itself when the boot flag is armed.

## Files

| File | Purpose |
|---|---|
| `README.md` | Scope, reference build, quick start, verification, rollback |
| `playbook.md` | The full procedure: model, gates, writer, offline application, pitfalls |

## Quick start for an agent

1. Profile the machine. If `services\version.txt` is not `30.0.33.176`, stop and re-run discovery.
2. Read `playbook.md` sections 1 to 3 and confirm the same gates exist.
3. Build the offline payload, swap it into the recovery image, arm one recovery boot.
4. Enter recovery (Shift + Restart, Troubleshoot, Advanced, Command Prompt, or let the payload run
   from `winpeshl.ini`).
5. Verify with section 7. A passing desktop is not verification until the machine has cold booted
   with the configuration engine disabled.

## Reference build

```text
kit                      27.0.65.370
services\version.txt     30.0.33.176
productcfg.exe           2020112   1d8111ebf3d9475a8bba6e3602c0a0ef2180430062ed62b8c8951090801d9e4e
iservconfig.dll          1031168   96144c639167959a2def8f82b5259fc88e4c0c9ed53e00ead5cf4188dbe32ebd
```

A different version means a different build. Re-run discovery; do not reuse the file names blindly.

## State before and after

| Store | Before | After |
|---|---|---|
| `Install\InstalledProductType` | 9 (`av_lite`) | 3 (`ts`) |
| `Install\RegisteredFeature` | `av_lite` | `ts` |
| `Install\InstalledProductName` | Bitdefender Antivirus Free | Bitdefender Ultimate Security |
| `HKLM\SOFTWARE\Bitdefender\Product ID` | 2760 | 2763 |
| `Install\SurveyDataInfo` | bundle `avlite` | bundle `ultimate_plan`, `server_product_type` 3 |
| `Security App\About\IsFreeApp` | 1 | 0 |
| `Security App\About\ShortProductName` | Antivirus Free | Ultimate Security |
| protection plugin set | `bdshieldsrv_plugins_av_lite.xml` (lite) | full ts set, `av_lite` added to `products=` |
| app plugin set | `bdappsrv_plugins_av_lite.xml` (87 plugins) | full ts set (106 plugins) |
| `product_features.json` | 29 `false` entries | 0 |
| `productcfg.exe` | present | renamed `.bak`, configuration pass cannot run |

## Verification

Runtime, not cosmetic:

```powershell
sc query Ignisv2                                                     # firewall driver RUNNING
Get-Process | Where-Object { $_.Modules.FileName -match 'igal\.dll' } # module loaded
```

UI, by automation id on `seccenter.exe`:

```text
idMainTitle            "Ultimate Security"
idProductInformation   "Bitdefender Ultimate Security | Build 27.0.65.370"
idStatusBarBtnUpgrade  "Licensed"
```

Dashboard must list Firewall, Advanced Threat Defense, Anti-tracker, VPN, Safepay, Vulnerability
Scan with no lock markers.

## What stays cosmetic

The countdown and the Free wording are language resources and can be changed. The subscription
counter, the account page text that comes from the server, and the encrypted `UserInfo` blobs are
licence state and cannot be forged locally. Feature access does not depend on them.

## Rollback

- `productcfg.exe.bak` and `productcfgplg.dll.bak` rename back with one script.
- Every edited language file keeps a `.bak`.
- `v.selfprotect.json.bkp` holds the original rule set.
- Keep the untouched recovery image before the first swap.

## Playbook

Open [`playbook.md`](playbook.md). Start at section 1.

## License

MIT. See the repository [`LICENSE`](../../../LICENSE).
