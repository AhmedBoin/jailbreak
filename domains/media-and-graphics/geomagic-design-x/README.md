# Geomagic Design X 2026.1

Domain: `media-and-graphics`

Target: Geomagic Design X 2026.1, build 2026.1.0.0327 (Hexagon), x64. Launcher `GeomagicDesignX.exe`; UI process `bin\RapidformMain.exe`; licence layer `bin\rfCommonBase.dll`.

Status: desktop verified on Windows 11 x64 on 2026-11-26. Offline; no `.cml`, serial, or licence server. The application stayed responsive for more than two minutes with the full ribbon.

## The result

Four in-memory `CRFLicense` patches plus the startup gate patch make the application report a Pro licence and build the complete command registry. The CimLM server still writes its own `License Error: No valid license` line; the application does not use that result for the UI.

| Module | Function or site | RVA | Patch |
|---|---|---:|---|
| `rfCommonBase.dll` | `CRFLicense::CheckLicense` | `0x8B790` | `B8 01 00 00 00 C3` |
| `rfCommonBase.dll` | `CRFLicense::GetLicenseCondition` | `0x769B0` | `B8 01 00 00 00 C3` |
| `rfCommonBase.dll` | `CRFLicense::GetLicenseType` | `0x769D0` | `48 B8 FF FF FF FF FF FF FF FF C3` |
| `rfCommonBase.dll` | `CRFLicense::IsProPack` | `0x8BD00` | `B0 01 C3` |
| `RapidformMain.exe` | startup gate | `0x6F5DA` | `B8 01 00 00 00 90 90 90 90 90 90 E9 D4 00 00 00 90` |

`RapidformMain.exe` and `rfCommonBase.dll` are Themida/WinLicense-packed. The gate bytes exist only after unpacking, so the gate is patched in memory. The `CRFLicense` functions are resolved by decorated export name at runtime; the RVAs are for the reference build and for verification only.

The window title becomes `Geomagic Design X 2026. 1. 0 [Pro] [Not for Resale]`. The ribbon contains HOME, LIVECAPTURE, POINTS, POLYGONS, REGION, TEXTURE, ALIGNMENT, SKETCH, 3D SKETCH, MODEL, and EXACT SURFACING. The MODEL tab exposes the full solid, surface, wizard, curve, and edit command set; HOME exposes SOLIDWORKS LiveTransfer.

## What is included

| File | Purpose |
|---|---|
| `README.md` | Scope, result, quick start, verification, update notes |
| `playbook.md` | Licence flow, exact sites, discovery for a new build, full patcher source, proxy delivery, build, install, rollback |

No binary, proxy DLL, patcher DLL, installer, licence file, or application file is stored here. The playbook contains the patcher source and the exact commands.

## Quick start

1. Close Geomagic Design X.
2. Build `Geomagic_Design_X_patcher.dll` from the source in section 7 of the playbook. The build command is:
   `cl /nologo /LD /O2 /MT gdxcrack.c /link /OUT:Geomagic_Design_X_patcher.dll psapi.lib`
3. Obtain the `LIBEAY32.dll` proxy from the 2024 RuntimePatcher repository and verify SHA256 `77CE8689722D93A0871946CD6BB867A90A6A369445D321AC1788F030E451AA74`. The URL and the compatibility evidence are in section 6 of the playbook.
4. As administrator, back up `bin\LIBEAY32.dll`, copy the proxy and the patcher into `bin`, and start the original `GeomagicDesignX.exe`.
5. Verify the title and the ribbon, and inspect `%TEMP%\gdxcrack.log` for the patch lines.
6. To undo, restore `bin\LIBEAY32.dll.gdxbak` and delete `bin\Geomagic_Design_X_patcher.dll`.

## Reference build

```text
GeomagicDesignX.exe              317,704   90835A4C338A14E148C69F6E57389AB2322D1282996A9AFE3C85DB43A09B0F02
bin\RapidformMain.exe          7,602,440   87F65D6BCC6D0277E615C039C53C174891FA028D1BE92A924B4E812CFFEFF74F
bin\rfCommonBase.dll           4,799,004   11BE22B433AFCA3B163E5D6A09B2920F280F498D25F8081DB2AA98B96666F47C
bin\LIBEAY32.dll (stock)       2,297,456   E748BA7FCDAF33D219891C0311A61AEBF8546047960793159AFC0824B5D40885
bin\LIBEAY32.dll (proxy)       2,285,056   77CE8689722D93A0871946CD6BB867A90A6A369445D321AC1788F030E451AA74
Geomagic_Design_X_patcher.dll    159,744   E56F814168F8DF8FEF8F8BE1B31E2055C8D2488B3188A8CE0F8D4AFDDABABDCA
```

The patcher hash is from a Visual Studio 2022 17.14 x64 build; the source is the authoritative artifact, so a different compiler may produce a different hash.

## Verification

- Title bar: `Geomagic Design X 2026. 1. 0 [Pro] [Not for Resale]`.
- Ribbon: the ten tabs above; MODEL shows Extrude, Revolve, Loft, Sweep, Surface, Wizard, Curve, Boolean, Fillet, Shell, Thicken Surface, Trim Surface, Sew, Transform Body, Move Face, Delete Face, Split Face, and the rest of the set.
- `C:\ProgramData\CLM\LicFiles\GeomagicDesignX` contains only `CLMConfig.xml` and `CimLmLib.log`; no `.cml` is present.
- `CimLmLib.log` still records `License Error: No valid license`; this is expected and does not block the UI.
- The process stays responsive for more than two minutes.
- Rollback restores `LIBEAY32.dll` to SHA256 `E748BA7FCDAF33D219891C0311A61AEBF8546047960793159AFC0824B5D40885`.

## Updates

An application update or repair replaces `bin\LIBEAY32.dll` and removes the patch. Delete `bin\LIBEAY32.dll.gdxbak`, run the install steps again, and refresh the backup. Recheck the gate RVA and the hashes before reusing the patcher on another build.

## Full playbook

Open [`playbook.md`](playbook.md).

## License

MIT. See the repository [`LICENSE`](../../../LICENSE).
