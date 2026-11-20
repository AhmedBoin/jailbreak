# Bitdefender Antivirus Free 27: conversion playbook

Target: Bitdefender Antivirus Free, kit 27.0.65.370, module version 30.0.33.176
Domain: `security-and-networking`
Status: verified on the reference build

This playbook is written to be executed by an agent with a command prompt, an administrator token,
and the ability to reboot into Windows Recovery Environment. It does not need source code, a server
account, a key, or a licence.

Everything below was run on the reference build. Where a step failed first, the failure is recorded,
because the failures are the expensive part.

## 1. The model

Three questions decide the approach.

1. **What is the gate?** Here it is not one thing. The protection service loads plugins from
   `settings\services\plugins\bdshieldsrv_plugins_av_lite.xml` and
   `bdauxsrv_plugins_av_lite.xml`; the app service loads its own set from
   `Security App\settings\services\plugins\bdappsrv_plugins_av_lite.xml`; and
   `product_features.json` gates individual features. The lite files are chosen by symlinks that
   point at the lite name.
2. **Who writes the state?** `productcfg.exe` and its in-process plugin `productcfgplg.dll` rewrite
   the product identity and the Free flags at every boot. `iservconfig.dll` re-registers services.
   `v.selfprotect.json` restores protection rules.
3. **Can you write where it lives?** No. Bitdefender's driver denies writes to every non-Bitdefender
   process, including an elevated administrator, and denies ACL changes too. The only write context
   is offline: recovery environment or Windows PE.

## 2. Inventory

```text
installer kit        27.0.65.370
module version       30.0.33.176  (services\version.txt)
program folder       C:\Program Files\Bitdefender\Bitdefender Security
app folder           C:\Program Files\Bitdefender\Bitdefender Security App
data folder          C:\ProgramData\Bitdefender
services             VSSERV, BDProtSrv, BDAuxSrv, BDAppSrv, UPDATESRV, ProductAgentService, bdredline
driver               Ignisv2 (firewall)
tasks                \Bitdefender Agent WatchDog_<guid>
identity             HKLM\SOFTWARE\Bitdefender\Install
```

Before values:

```text
InstalledProductType 9      InstalledProductName Bitdefender Antivirus Free
RegisteredFeature    av_lite   Product ID        2760
```

## 3. The gates

### 3.1 Plugin sets, one per service

```text
Security\settings\bdshieldsrv_plugins.xml -> settings\services\plugins\bdshieldsrv_plugins_av_lite.xml
Security\settings\bdauxsrv_plugins.xml    -> settings\services\plugins\bdauxsrv_plugins_av_lite.xml
Security\settings\cst_sdk_vsserv.cfg       -> cst_sdk_vsserv_av_lite.cfg
App\settings\bdappsrv_plugins.xml         -> settings\services\plugins\bdappsrv_plugins_av_lite.xml
```

The full sets (`*_ts.xml`) are already on disk. `ts` and `epp_privacy` are byte identical. Do not
recreate the symlinks; overwrite the file the symlink points at, and allow `av_lite` in every
`products="..."` list:

```powershell
$t = [IO.File]::ReadAllText($src)
$t = [regex]::Replace($t, 'products="(?!av_lite)', 'products="av_lite,')
[IO.File]::WriteAllText($dst, $t, [Text.Encoding]::UTF8)
```

The app set matters as much as the protection set: the lite set has 87 plugins, the ts set has 106,
and the 19 missing ones are the panels (firewall client, camera and microphone protection, profiles,
scam radar, vulnerability, ransomware logger, antispam). Patch only the protection set and the
engines run while the window keeps its padlocks.

### 3.2 Feature gate

`product_features.json` holds one entry per feature with `"allowed": false` (29 of them). Write a
version with every feature allowed, in the protection settings folder and in the app settings folder.

### 3.3 Language resources

What the window shows is often text, not state. In `App\lang\en-US`:

```text
seccenter.txtui       "%d days left", "%d protection days left"
bdgs.txtui            "Antivirus Free"
intermsec.txtui       "Antivirus Free"
dynamicupsell.txtui   "Antivirus Free"
```

Replacing the countdown template with a literal removes the number. Keep a `.bak` of each file.

## 4. The writer

`productcfg.exe` carries `IsFreeApp`, `InstalledProductType` and `ShortProductName` together, and
its plugin runs inside `bdservicehost`. That is why every registry change made live, or even offline
without touching the writer, is reverted on the next boot. Rename it offline:

```bat
attrib -r -s -h "%SEC%\productcfg.exe"
ren "%SEC%\productcfg.exe" "productcfg.exe.bak"
ren "%SEC%\productcfgplg.dll" "productcfgplg.dll.bak"
```

A rename is reversible, a stub is not. Ship a `revert.cmd` that renames both back.

`iservconfig.dll` re-enables the services. Let it. Services are supposed to run; only the
configuration engine had to stay dead.

## 5. Offline application

### 5.1 Why Safe Mode is not an option

Entering Safe Mode needs `bcdedit /set {default} safeboot minimal`. Bitdefender denies that write
while it runs (`Access is denied`), and its BCD protection is active even for an administrator.
Service keys and `SafeBoot\Minimal` entries are writable, but there is no way to set the flag.

### 5.2 Recovery environment

Bitdefender does not load there. Entry:

1. `reagentc /boottore` sets a one-time recovery boot. It was armed and the machine still started
   Windows, so treat it as best effort.
2. Manual is deterministic: hold Shift, click Restart, Troubleshoot, Advanced options, Command
   Prompt, then run `X:\Windows\System32\bdpay.cmd`.

### 5.3 Payload

The recovery image needs the payload, its data files, and a shell hook:

```text
Windows\System32\bdpay.cmd
Windows\System32\bdshield.xml, bdaux.xml, bdappsrv.xml, bdcst.cfg,
                 bdgate.json, bdselfprot.json, lang_*.txtui
Windows\System32\winpeshl.ini
```

```ini
[LaunchApps]
X:\Windows\System32\cmd.exe, /c X:\Windows\System32\bdpay.cmd
X:\sources\recovery\recenv.exe
```

Use literal `X:` paths. Run `wpeinit` first, then poll for the Windows volume; letters are not
assigned instantly:

```bat
wpeinit >nul 2>&1
:findvol
for %%D in (C D E F G H I J K L M N O P Q R S T U V W Y Z) do (
    if not defined BDVOL if exist "%%D:\Windows\System32\config\SOFTWARE" set "BDVOL=%%D:"
)
```

Log to the recovery partition and to `C:\bdpay.log`. On failure print the reason and pause; a silent
exit costs a reboot per attempt.

### 5.4 Write order

1. self-protection rules trimmed (`v.selfprotect.json` and `.bkp`)
2. plugin sets for protection and app services
3. service config `cst_sdk_vsserv_av_lite.cfg`
4. feature gate in both folders
5. language files with `.bak` copies
6. identity and About values in the offline SOFTWARE hive
7. service `Start` values in the offline SYSTEM hive, all control sets
8. repair tasks deleted
9. `productcfg.exe` and `productcfgplg.dll` renamed
10. hosts entries for `nimbus.bitdefender.net`

```bat
reg load HKLM\BDOFF "%BDVOL%\Windows\System32\config\SOFTWARE"
reg add "HKLM\BDOFF\Bitdefender\Install" /v InstalledProductType /t REG_DWORD /d 3 /f
reg add "HKLM\BDOFF\Bitdefender\Install" /v RegisteredFeature /t REG_SZ /d ts /f
reg add "HKLM\BDOFF\Bitdefender" /v "Product ID" /t REG_SZ /d 2763 /f
reg unload HKLM\BDOFF
```

## 6. Real state and cosmetic text

| Item | Kind | Effect |
|---|---|---|
| protection plugin set | gate | engines load |
| app plugin set | gate | panels appear and open |
| `product_features.json` | gate | features enabled |
| `InstalledProductType`, `RegisteredFeature` | gate | identity, module selection |
| `productcfg.exe` | writer | rewrites Free at every boot |
| `IsFreeApp`, `ShortProductName` | display, same writer | stable once the writer is gone |
| `%d days left` | language text | cosmetic |
| `UserInfo`, `UserInfoEx2` | encrypted licence | real subscription, not forgeable locally |

## 7. Verification

```powershell
sc query Ignisv2
Get-Process | Where-Object { $_.Modules.FileName -match 'igal\.dll' }
(Get-ChildItem 'C:\Program Files\Bitdefender\Bitdefender Security\settings\firewall' -File).Count
```

UI Automation on `seccenter.exe`:

```text
idMainTitle            "Ultimate Security"
idProductInformation   "Bitdefender Ultimate Security | Build 27.0.65.370"
idStatusBarBtnUpgrade  "Licensed"
```

Then confirm the dashboard lists Firewall, Advanced Threat Defense, Anti-tracker, VPN, Safepay and
Vulnerability Scan with no lock markers. Finally cold boot and check again: the writer acts at boot,
so only post-boot verification counts.

## 8. Pitfalls from the reference run

1. `icacls /deny` fails on the protected folder; the block is the driver, not the ACL.
2. `bcdedit /set safeboot` is denied, so Safe Mode automation is impossible.
3. `reagentc /boottore` can be armed and ignored; keep the Shift+Restart path documented.
4. Deleting the task is not enough to stop service re-registration; `iservconfig.dll` does it.
5. Recreating the symlink is unnecessary; the link target file is what matters.
6. The app service has its own plugin set; miss it and the padlocks stay.
7. Language files change what the window says, and only what it says.
8. Anything read from the licence blob stays wrong; do not chase the counter.
9. A passing desktop is not a passing reboot.

## 9. Packaging

One self-contained `.bat` that self-elevates, unpacks its kit to `C:\_BD`, generates every
machine-specific file from the local install, copies the live `winre.wim`, mounts it with DISM,
injects payload and data, verifies every file, commits, swaps the live image, arms one recovery
boot, and restarts on a cancellable countdown.

Generation must run on the target. The playbook ships a procedure; the image is machine specific.

## 10. Rollback

- `productcfg.exe.bak` and `productcfgplg.dll.bak` restore with one script.
- Language files keep `.bak` copies.
- `v.selfprotect.json.bkp` holds the original rules.
- Keep the untouched recovery image from before the first swap.
- Run the restore once before relying on it.
