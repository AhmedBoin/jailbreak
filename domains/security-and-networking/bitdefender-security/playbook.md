# Bitdefender Security Playbook

Target: Bitdefender Antivirus Free, kit 27.0.65.370 (product version 30.0.33.176), Windows x64.
Domain: `security-and-networking`
Status: model verified on the reference build. This document is a methodology, not a payload.

This playbook teaches an agent how to determine whether a Bitdefender kit is an edition switch,
how to find the state stores of the edition on the build in front of it, how to change that state
offline, and how to prove the result. It does not contain a patcher, a converted state, a kit, an
installer, a key, or a subscription.

The reference build values appear as evidence. They are not constants. A different build must be
re-profiled with section 4 before anything is written.

---

## 0. Contract

### 0.1 What "cracked" means here

The target is converted only when all of the following hold after a cold boot, with no account
change and no network:

| Property | Evidence |
|---|---|
| Product type is Total Security | `HKLM\SOFTWARE\Bitdefender\Install\InstalledProductType` = `0x3` |
| Feature gate is Total Security | `RegisteredFeature` = `bdts` |
| Product name is Total Security | `Install\InstalledProductName` and `About\ProductName` both read `Bitdefender Total Security` |
| Product ID is the Total Security id | `HKLM\SOFTWARE\Bitdefender\Product ID` = `2763` on the reference build |
| Every endpoint feature is allowed | `FeaturesController\data` has 15 of 15 features with `allowed:true` |
| The Total Security module set is loaded | the two plugin XMLs and `cst_sdk_vsserv.cfg` resolve to the Total Security variants |
| The subscription cache agrees | the `Sub_ID_*` JSON has the Total Security bundle, `IsValid:true`, 15 features |
| The firewall engine runs | `sc query Ignisv2` is `RUNNING`, `ignis_core.dll` is loaded in `bdservicehost.exe` |
| The UI reports the edition | title bar `Bitdefender Total Security`, Protection lists Firewall, Antispam, Vulnerability Scan, Ransomware Remediation |
| The change is offline-only | no ATC `Malicious behavior blocked` event, no account sign-in change |

One failed row means the conversion is incomplete. A registry value alone is never evidence. A
screenshot of a title bar is never evidence. The matrix is the gate.

### 0.2 The one rule

**Write the state the product reads at boot, from outside the running product.**

The edition is decided by configuration, not by code. That configuration is protected in kernel
mode while Windows runs. Every live route fails (section 3.3). The only reliable write is the offline
hive plus the files under the product's `settings\` directory, from Windows Recovery Environment or
Windows PE. One offline session, in the right order, is the whole crack.

### 0.3 How an agent should use this document

Read in this order: `README.md`, this section, section 1, section 3, section 4, then section 5.

1. **Profile.** Record the installer version, `version.txt`, the Windows volume letter, BitLocker
   state, the product directory, and the service/driver list. If `version.txt` does not match the
   reference, do not reuse the values; section 4 is mandatory.
2. **Prove the model.** Confirm that every edition ships in the same payload: the installer contains
   Total Security files, and `install_config.xml` lists every edition's product id and module list.
   If the payloads differ per edition, this model does not apply; stop.
3. **Discover.** Walk section 4 on the target. Fill the discovery sheet (4.9) with the target's own
   values: product ids, module list, feature ids, plugin-set names, subscription path and JSON
   fields, product-name key. Do not copy the reference values into a write step without matching
   them against the target.
4. **Apply offline.** Section 5. Back up before writing. The order matters: identity and name first,
   because the name decides which `Config` key the product reads; the module list after the rename;
   the plugin sets last.
5. **Verify.** Section 6, cold boot, all rows. Return the evidence listed in 0.3.7.
6. **Stop conditions.** A different `version.txt`; a different installer vendor; a per-edition
   payload; a missing `install_config.xml`; a product that no longer resolves `Config` from the
   product name; a write that returns `0x5` while the drivers are loaded. In any of these, stop and
   re-profile instead of forcing the reference values.
7. **Evidence to return.** The discovery sheet, the backup listing, the registry/file changes,
   `Verify` output, plugin counts, `sc query`, and a screenshot of the Protection page.

### 0.4 What this document deliberately does not include

- No installer, no patched binary, no keygen, no licence key, no subscription.
- No ready-to-import `.reg` files, no batch scripts, no converted hive, no tooling kit.
- No reference-machine identifiers copied as if they were the target's.

The agent builds the state from the target's own build and the target's own identifiers. That is the
difference between a playbook and a crack.

### 0.5 Scope

Use this on software you own or are authorised to modify. The procedure changes edition state on a
local endpoint; it does not create a subscription, a key, or an account entitlement, and it does not
touch Bitdefender's servers.

---

## 1. Target profile

| Item | Value |
|---|---|
| Vendor | Bitdefender SRL |
| Product | Bitdefender Antivirus Free, kit 27.0.65.370 |
| Product version | 30.0.33.176 (`version.txt`, file version of every module) |
| Install path (product) | `C:\Program Files\Bitdefender\Bitdefender Security\` |
| Install path (UI) | `C:\Program Files\Bitdefender\Bitdefender Security App\` |
| Install path (agent) | `C:\Program Files\Bitdefender Agent\` |
| Data path | `C:\ProgramData\Bitdefender\` |
| Architecture | x64 only |
| Framework | native C++ with MSVC runtime, nlohmann JSON, Sciter and WebView2 for UI |
| Protector | Bitdefender self-protection in kernel mode, Authenticode allowlisting |
| Update mechanism | `UPDATESRV`, `updatesrv.exe`, `redline`, update host from `install_config.xml` |

Services:

```text
VSSERV             Bitdefender Virus Shield            (the product itself)
BDAuxSrv           Bitdefender Auxiliary Service       (plugin host)
BDProtSrv          Bitdefender Protected Service
BDAppSrv           Bitdefender App Service
UPDATESRV          Bitdefender Desktop Update Service
BDSafepaySrv       Bitdefender Safepay Service
bdredline          Bitdefender RedLine Service
bdredline_agent    Bitdefender Agent RedLine Service
```

Kernel drivers, all relevant to section 3:

```text
vlflt.sys      Start=0  Boot    Group=FSFilter Anti-Virus
atc.sys        Start=1  System  Group=FSFilter Anti-Virus
gemma.sys      Start=1  System  Group=FSFilter Anti-Virus
Trufos.sys     Start=2  Auto    Group=Boot Bus Extender
BdDci4.sys     Start=2  Auto
ignisv2.sys    Start=2  Auto    (firewall engine, WFP)
bdelam.sys     Start=0  Boot    (ELAM, stopped once booted)
bdprivmon.sys  Start=3  Manual
bduefiscan.sys Start=3  Manual
```

The kit is a single installer. `securityproductinformation.ini` in the install directory says
`Name=Bitdefender Total Security`. The free edition is selected by configuration, not by a different
payload. Every Total Security plugin, driver and configuration file is already on disk.

---

## 2. Reference build

Recorded from the converted machine. A tool or a write step should refuse a different `version.txt`.

```text
file                     size      sha256
featurescontroller.dll   682808    e1dc870318cf1cd14cc827f8e1ef80eae00e8c5d419c67e1d84e444bb10f228c
subscriptional.dll       659512    d23633366e3b765559964da52df25ce08db0e0dc752ca7e73ef59444356d3123
install_config.xml        14511    222126ac4fc11b7894dfa938e1de6b17b1463cd93aeb7095e7e480e7e4f68f29
product_features.json      2935    4a3bd19065af369a140e8372c2f21d756c55005b0735a211d7454517cc52b858
epaas_acl.json            25391    2308f2ec83fbf15d3b79e0ff1619a4329c5019225f0a680f9b3e6a9623c7a559
epaas_config.json          3153    b331e8363f7cccc9ce66c2ba23e610aab77444ce95eb0c12f896f9e843872e49
bdservicehost.exe        859456    50f61ec398b5a7cf1e0935c20c5e69335a75bbe880411d3d6def7cba13ab336f
productcfg.exe          2020112    1d8111ebf3d9475a8bba6e3602c0a0ef2180430062ed62b8c8951090801d9e4e
seccenter.exe           2741632    f199b5d453e989128228c29db03914946e2a5e31e60b53c9bdb31b92ac7c9132
version.txt                  11    e032cfab1ac059b76e3446554d82e1c2da252d8ebf20a6642ca7f0057b7549bb
```

The installer reports `27.0.65.370`; `version.txt` and every product module report `30.0.33.176`.

---

## 3. The model

### 3.1 One payload, many editions

Prove it before planning anything:

1. The installer is one product. `securityproductinformation.ini` names Total Security even on a
   free install.
2. `settings\install_config.xml` lists every edition and every module list in the same file.
3. `settings\services\plugins\` contains the plugin set for every edition.
4. The free install has the Total Security files on disk; only the selection differs.

If a build ships different binaries per edition, or the Total Security plugin files are absent, this
model does not apply.

### 3.2 The state stores

Everything that decides the edition:

| Layer | Store | What it decides |
|---|---|---|
| Product identity | `HKLM\SOFTWARE\Bitdefender\Install` | product type, feature gate, display name, survey JSON |
| Product id | `HKLM\SOFTWARE\Bitdefender\Product ID` | edition id used by UI and update logic |
| Module list | `HKLM\SOFTWARE\Bitdefender\<PRODUCT_FULL_NAME>\Config` | which modules the product starts |
| Feature flags | `HKLM\SOFTWARE\Bitdefender\FeaturesController\data` | which features the bus allows |
| Plugin sets | three files under `<product>\settings\` | which plugin DLLs the services load |
| Subscription cache | `HKU\.DEFAULT\Software\Sub_ID_<app id>` | what the product believes is licensed |
| Display name | `HKLM\SOFTWARE\Bitdefender Security App\About\ProductName` | the key name used to resolve `Config` |

There are six stores: identity, id, modules, features, plugins, subscription. The
display name is both a value and a lookup key; that is the trap in section 9.

### 3.3 Why live writes fail

Every one of these was executed on the reference build. `0x5` is `ERROR_ACCESS_DENIED`.

| Attempt | Result |
|---|---|
| `Set-ItemProperty HKLM:\SOFTWARE\Bitdefender\FeaturesController` as Administrator | `0x5` |
| Same write as `NT AUTHORITY\SYSTEM` from a scheduled task | `0x5` |
| Write the subscription key under `HKU\.DEFAULT` | `0x5` |
| Write a service `Start` value back to itself | `0x5` |
| Create a file in the product directory | `0x5` |
| Write through a directory junction into the product directory | `0x5` |
| Write through a volume GUID path | `0x5` |
| Write through `\\?\GLOBALROOT\Device\HarddiskVolumeN\...` | `0x5` |
| Registry symbolic link key pointing at the protected key | `0x5` on write |
| `RegSaveKey` + `RegRestoreKey` on a protected key | save `0`, restore `0x5` |
| `VirtualAllocEx` into product processes | `0x5` |
| `NtMapViewOfSection` into `bdservicehost.exe` | `0xC0000022` |
| Code in a signed agent service running as SYSTEM | executes, writes `0x5` |
| Pristine signed executable copied outside the product directory | executes, writes `0x5` |
| `sc stop VSSERV`, `fltmc unload Trufos` | `1052`, `0x80070005` |

`sc stop` returns `1052` because the service handler does not accept stops, not because of the
filter. `fltmc unload` is denied by the self-protection driver. Executing code is not enough; the
allowlist is path based.

### 3.4 The trust boundary

`productcfg.exe` can perform `RegSetInfoKey` on the protected keys because it runs from
`C:\Program Files\Bitdefender\Bitdefender Security\`. The same image from Common Files, or a
Bitdefender-signed `bdagent.exe` copied elsewhere, is denied. Signer and file name are not enough;
the image path is. That is why a write from inside Windows is a dead end and the offline hive is the
route.

### 3.5 Safe Mode and the IPC bus

- `Trufos.sys` is `Group=Boot Bus Extender`; both `SafeBoot\Minimal` and `SafeBoot\Network` load
  that group. Safe Mode is not a bypass.
- The feature state is served over the epaas bus. `settings\epaas_acl.json` grants
  `set_feature_allowed_state`, `set_product_allowed_state` and
  `subscription\activate_custom_level` only to clients whose subject is `Bitdefender SRL`. That is an
  Authenticode check on the calling image; a clean client library without Bitdefender's signature
  cannot use it.
- ATC is behaviour based. Copying a system binary into the product directory to abuse path trust
  raises `Malicious behavior blocked`. The offline procedure never runs inside Windows, so it
  produces no ATC event.

---

## 4. Discovery

Do this on the target build, not from this document. Record every value in the sheet at 4.9.

### 4.1 Inventory

```text
type "C:\Program Files\Bitdefender\Bitdefender Security\version.txt"
reg query "HKLM\SOFTWARE\Bitdefender\Install"
reg query "HKLM\SOFTWARE\Bitdefender" /v "Product ID"
reg query "HKLM\SOFTWARE\Bitdefender Security App\About" /v ProductName
sc query type= service state= all | findstr /i "Bitdefender"
driverquery /v | findstr /i "vlflt atc gemma Trufos BdDci4 ignis"
```

Also record the installer version from Apps & Features or the setup package, and the product
directory listing (`settings\`, `settings\services\plugins\`, `version.txt`).

### 4.2 Edition table

Open `<product>\settings\install_config.xml`. It lists, for every edition:

- `ProductIDAVLite`, `ProductIDAV`, `ProductIDIS`, `ProductIDTS`, `ProductIDEPP`, `ProductIDVSB`
- `ConfigAVLite`, `ConfigAV`, `ConfigIS`, `ConfigTS`, `ConfigEPP`, `ConfigVSB`
- `ShortProductName*`

The module list is a comma-separated set of two-letter codes (`OA`, `OD`, `AS`, `AC`, `AP`, `FW`,
`PC`, `EC`, `FV`, `BK`, `TP`, `HM`, `RG`, `MD`, `PR`, `VL`, `PT`, `UP`, `IS`, `ST`, `SI`, `OS`,
`WL`, `SF`, `DA`, `CP`, `VP`, `AT`, `ATD`, `QR`, `WP`, `AMSI`, `FS`, `RP`, `DL`, `RCA`, `CMP`).
Record the target edition's id and list verbatim.

The UI renders its cards from this value, not from the feature flags. A conversion that sets every
feature flag but leaves the lite module list shows only Antivirus, Advanced Threat Defense,
Cryptomining Protection and Online Threat Prevention.

### 4.3 Name to type mapping

`subscriptional.dll` contains wide-string compares that map the feature name to the product type:

```text
bdts          -> 3     Total Security
bdis          -> 2     Internet Security
bdav          -> 1     Antivirus Plus
epp           -> 7
epp_privacy   -> 8
av_lite       -> 9     Antivirus Free
```

On the reference build the mapping is at `0x18004DF90`. Do not hardcode that address; find the
strings and the integer returns next to them in the target DLL. The value stored in
`Install\InstalledProductType` must be the mapped integer, and `RegisteredFeature` must be the name.

### 4.4 Feature ids

Two files define the feature vocabulary:

- `settings\product_features.json` lists every feature id and its default state.
- `settings\epaas_config.json` maps each module to its handler and gives
  `modules_bitmask_indices`, the authoritative feature-id list for the bus.

`featurescontroller.dll` holds the message names (`set_feature_allowed_state`, `set_feature_state`,
`set_feature_reporting_state`, `get_feature_state`, `get_all_feature_states`) and the registry value
name `data`. It imports `RegGetValueW`, `RegSetValueExW`, `RegCreateKeyExW`, so the value it
persists is local.

Read the current value:

```text
reg query "HKLM\SOFTWARE\Bitdefender\FeaturesController" /v data
```

The JSON is `{"features":{<id>:{"allowed":<bool>,"reporting":<bool>}, ...}}`. Count the
`"allowed":true` entries. On the free edition the reference build had 3 of 15; Total Security
allows all 15. Use the target's own feature ids from `epaas_config.json`; do not assume 15 if the
build defines more or fewer.

### 4.5 Plugin sets

List the directory:

```text
dir /b "C:\Program Files\Bitdefender\Bitdefender Security\settings\services\plugins\*_plugins_*.xml"
dir /b "C:\Program Files\Bitdefender\Bitdefender Security\settings\cst_sdk_vsserv*.cfg"
```

The active files are symbolic links in `settings\`:

```text
bdauxsrv_plugins.xml    -> services\plugins\bdauxsrv_plugins_<edition>.xml
bdshieldsrv_plugins.xml -> services\plugins\bdshieldsrv_plugins_<edition>.xml
cst_sdk_vsserv.cfg      -> cst_sdk_vsserv_<variant>.cfg
```

Read the link target to learn the current edition. On the reference build the free set had 54 and
102 plugins; the Total Security set has 73 and 119, and `cst_sdk_vsserv_regular.cfg`. The TS sets add
`firewall_epaas_module`, `antispam_epaas_module`, `anti_tracker_epaas_module`,
`safepay_epaas_broker_module`, `ransomware_epaas_module`, `vulnerability_epaas_module`,
`camera_protection_epaas_module`, `microphone_monitor_epaas_module`, `tuneup_epaas_module`,
`fileshredder_epaas_module`, `antitheft_epaas_module`, `privprot`, `appExploitsTools`,
`win_store_app_provider_epaas_module`, `scan_amsi`.

Replacing a link with a regular file that contains the target edition's XML is equivalent for the
loader and avoids symlink privileges. Delete the link before copying.

### 4.6 Subscription cache

Find the application id:

- `settings\bootstrapdata.json` has the `commercial_details_id` context.
- `HKLM\SOFTWARE\Bitdefender\Install\SurveyDataInfo` has `bundle_id`.

The cache key is `HKU\.DEFAULT\Software\Sub_ID_<app id>`. On the reference build:

```text
HKU\.DEFAULT\Software\Sub_ID_com.bitdefender.cl
  DATA              REG_SZ    JSON
  ServerProductType REG_DWORD 9 -> 3
  PrevProductType   REG_SZ    bdav -> bdts
```

The JSON keys are stable: `Bundle`, `ServerProductType`, `IsValid`, `Expiry`, `Features`,
`CommercialID`, `ServiceID`. `Expiry` is a Unix timestamp. `CommercialID` and `ServiceID` are
device-bound: keep the target machine's values. Never copy the reference machine's identifiers onto
another device; a mismatch is at best ignored and at worst resets the cache.

### 4.7 Product name key

`HKLM\SOFTWARE\Bitdefender Security App\About\ProductName` is read into `PRODUCT_FULL_NAME`, and the
product then resolves:

```text
HKLM\SOFTWARE\Bitdefender\%PRODUCT_FULL_NAME%\Config
```

Character for character. After changing the name to `Bitdefender Total Security`, the product reads
`HKLM\SOFTWARE\Bitdefender\Bitdefender Total Security\Config`. The old key remains for anything that
still resolves the old name, which is why the module list is written to both keys during the change.

### 4.8 Prove the trust boundary

Before planning a write, confirm the model on the target:

1. Drop a probe executable into a candidate directory (not the product directory), run it as SYSTEM,
   and try to create a file in the product directory.
2. `ERROR_ACCESS_DENIED` means the directory is not trusted and the live route is closed.
3. Success would mean the allowlist is not path based on this build; re-evaluate the model before
   continuing.

Do not use an unsigned probe in the product directory to "test" trust; ATC will flag the behaviour.

### 4.9 Discovery sheet

Fill this in before any write:

| Field | Target value |
|---|---|
| Installer version | |
| `version.txt` + SHA-256 | |
| Product directory | |
| Windows volume in recovery | |
| BitLocker | |
| Free product type / name / feature | |
| Target product type / name / feature | |
| Target `Product ID` | |
| Target `Config` list | |
| Feature ids (count) | |
| Plugin set names + counts | |
| `cst_sdk_vsserv` variant | |
| `Sub_ID` key + bundle | |
| `CommercialID` / `ServiceID` (keep) | |
| Trust-boundary probe result | |

---

## 5. Application

### 5.1 Choose the environment

Windows Recovery Environment or Windows PE. In WinRE the Windows volume may not be `C:`; detect it
by probing `\Windows\System32\config\SOFTWARE` on each letter. Unlock BitLocker first, or `reg load`
fails. Do not use Safe Mode (section 3.5).

```text
shutdown /r /o /t 0
Troubleshoot > Advanced options > Command Prompt
```

The copy of this playbook and any notes must be readable from the recovery console. Keep them on the
Windows volume or on removable media; WinRE has `cmd`, `reg`, `copy`, `del`, `attrib` only.

### 5.2 Mount the hives

```text
reg load HKLM\BD_SOFT <volume>\Windows\System32\config\SOFTWARE
reg load HKLM\BD_DEF  <volume>\Windows\System32\config\DEFAULT
```

If either load fails, unload the other and stop. A loaded hive that is edited halfway leaves the
machine in a mixed state.

### 5.3 Back up first

Export the two keys and copy the three active plugin files. The reference layout:

```text
<volume>\BDUnlockBackup\Bitdefender.reg
<volume>\BDUnlockBackup\SubID.reg
<volume>\BDUnlockBackup\bdauxsrv_plugins.xml.bak
<volume>\BDUnlockBackup\bdshieldsrv_plugins.xml.bak
<volume>\BDUnlockBackup\cst_sdk_vsserv.cfg.bak
```

The active plugin files are absolute symlinks; in WinRE the target may not resolve. Back up the
edition-specific source files instead, and note which link pointed where.

### 5.4 Write the state

Build the values from the discovery sheet, not from this document. The shape is:

1. **Identity** in `HKLM\BD_SOFT\Bitdefender\Install`: product type (dword), feature name (string),
   display name (string), survey JSON (string) with the target bundle and product type.
2. **Product id** in `HKLM\BD_SOFT\Bitdefender`: the target edition id.
3. **Display name** in `HKLM\BD_SOFT\Bitdefender Security App\About`: `ProductName` and
   `ShortProductName`.
4. **Module list** in `HKLM\BD_SOFT\Bitdefender\<target name>` and the old name key: the target
   edition's `Config` list verbatim from `install_config.xml`. The new key must exist in the same
   write, or the renamed product boots without a module list.
5. **Feature flags** in `HKLM\BD_SOFT\Bitdefender\FeaturesController\data`: the JSON with every
   target feature `allowed:true`. Preserve the schema and the target's own feature ids.
6. **Subscription cache** in `HKLM\BD_DEF\Software\Sub_ID_<app id>`: the target bundle, the target
   product type, `IsValid:true`, an `Expiry` in the future, the feature list, and the machine's own
   `CommercialID` and `ServiceID`.
7. **Plugin sets**: delete the three links and copy the target edition's XML/cfg into place as
   regular files.

Values must be exact. A name with a trailing space, a module code removed by a typo, or a feature id
that does not exist in `epaas_config.json` produces a partial conversion, not an error.

### 5.5 Order and failure handling

Order: identity and name -> module list -> features -> subscription -> plugin sets -> unload -> boot.

- Write the new `Config` key in the same step as the rename.
- Write the module list to both the old and new name keys.
- Import merges; to restore exactly, delete the values before importing a backup.
- If any write fails, stop and unload both hives. Do not boot a half-written state.
- After the writes, `reg unload` both hives and flush.

### 5.6 First boot

Boot normally. No boot setting is changed. The product restarts with the new state. If the UI still
shows the free edition, `Config` is still the lite list; if the product starts with no modules, the
new name key was not created before the rename.

---

## 6. Verification

### 6.1 Cold boot

Reboot once. Verify after the reboot, not before.

### 6.2 Registry

```text
reg query "HKLM\SOFTWARE\Bitdefender\Install" /v InstalledProductType
reg query "HKLM\SOFTWARE\Bitdefender\Install" /v InstalledProductName
reg query "HKLM\SOFTWARE\Bitdefender" /v "Product ID"
reg query "HKLM\SOFTWARE\Bitdefender Security App\About" /v ProductName
reg query "HKLM\SOFTWARE\Bitdefender\FeaturesController" /v data
```

Expected on the reference build: `0x3`, `Bitdefender Total Security`, `2763`, `Bitdefender Total
Security`, 15 allowed features. On another build, the values come from the discovery sheet.

### 6.3 Configuration

```text
findstr /c:"firewall_epaas_module"     "<product>\settings\bdshieldsrv_plugins.xml"
findstr /c:"anti_tracker_epaas_module" "<product>\settings\bdauxsrv_plugins.xml"
```

Count the plugins (`findstr /c:"<plugin " | find /c`) and compare with the target set. Check
`cst_sdk_vsserv.cfg` size or content against the regular variant.

### 6.4 Runtime

```text
tasklist /m /fi "imagename eq bdservicehost.exe" | findstr /i "bdtrackersel bdwfagplg bdwfntf ignis_core RansomwareRecoverAL vulnerabilityal igal bdsafepayservice tuneup fileshredder"
sc query Ignisv2
```

Expected: the Total Security module DLLs loaded in at least one `bdservicehost.exe`, `Ignisv2`
`RUNNING`. The firewall starts disabled after the conversion; switch it on once in Protection.

### 6.5 UI

Title bar `Bitdefender Total Security`. Protection lists Antivirus, Advanced Threat Defense,
Firewall, Antispam, Vulnerability Scan, Ransomware Remediation. Privacy lists Safepay and
Anti-tracker. Utilities lists Anti-Theft and OneClick Optimizer.

### 6.6 Negative checks

- No free-edition upgrade prompt.
- No `ATC` event for the procedure (it never runs inside Windows).
- No account sign-in change.
- No new subscription, key, or device added to an account.

---

## 7. Rollback

The exports and file backups from 5.3 are the rollback. Offline:

```text
reg load HKLM\BD_SOFT <volume>\Windows\System32\config\SOFTWARE
reg load HKLM\BD_DEF  <volume>\Windows\System32\config\DEFAULT
reg import <volume>\BDUnlockBackup\Bitdefender.reg
reg import <volume>\BDUnlockBackup\SubID.reg
reg unload HKLM\BD_SOFT
reg unload HKLM\BD_DEF
```

Then restore the three plugin files. If a `.bak` is missing, use the `_av_lite` source from
`services\plugins\` or `cst_sdk_vsserv_av_lite.cfg`. A full rollback returns the product type to the
free value, `RegisteredFeature` to `av_lite`, the name to Bitdefender Antivirus Free, the plugin sets
to the lite variants, and the feature flags to the free set.

Rollback is part of the playbook even when the operator says they do not want it. A write step
without a restore path is not a procedure.

---

## 8. Drift and new builds

| Change | Effect | Action |
|---|---|---|
| Minor update | plugin XMLs and `Config` usually untouched | nothing |
| Major version | new `install_config.xml`, new module codes, new feature ids | re-run section 4; rebuild the values |
| Engine update | none | nothing |
| Account subscription refresh | can re-point plugin sets and lower feature flags | re-apply after the refresh |
| Uninstall | n/a | roll back first if the uninstaller refuses the changed state |

A durable sign-out is not available in this build: My Account offers only Switch Account, and
deleting the user from `.usr` does not hold because the product restores it from `UserInfo` and
`UserInfoEx2`. Removing all three also removes the account the cached subscription is attached to,
so the feature flags may reset. The safe default is to stay signed in and re-apply after a refresh.

### 8.1 Re-profiling checklist

1. `version.txt` and hashes.
2. Edition table in `install_config.xml`.
3. Name-to-type strings in `subscriptional.dll`.
4. Feature ids in `product_features.json` / `epaas_config.json`.
5. Feature store value name and schema in `featurescontroller.dll`.
6. Plugin set names in `settings\services\plugins\`.
7. Subscription key and JSON keys.
8. Product-name key resolution.
9. Trust-boundary probe.

### 8.2 When to stop

- The Total Security payload is not present in the free kit.
- The edition is selected by a signed server response with no local cache.
- The product no longer resolves `Config` from the product name.
- The protection model has changed and the offline hive is also protected (for example, encrypted
  configuration outside the registry).
- The build is not Bitdefender or not the same product family.

---

## 9. Pitfalls

- **Absolute symlinks in WinRE.** The three active config files are symlinks with an absolute
  `C:\...` target. In WinRE the Windows volume may be another letter; reading through the link fails.
  Back up the edition sources, delete the link, copy the replacement.
- **No PowerShell in WinRE.** `cmd`, `reg`, `copy`, `del`, `attrib` only.
- **Batch quoting.** `if "%VAR:~-1%"=="\"` breaks the parser. Compare against `\x` or drop the check.
- **`reg import` merges.** To restore exactly, delete the values first.
- **Two module keys.** After the rename the product reads the new name key; anything that resolves
  the old name still reads the old key. Write both.
- **`Product ID` matters.** The UI and update logic key on it.
- **Firewall driver name.** `Ignisv2` in this build; older documentation says `bdfwfpf`.
- **Cloud features stay cloud.** VPN quota, Password Manager and Parental Control are server side.
- **ATC is behaviour based.** The offline procedure produces no event; live experiments do.
- **The subscription cache is device bound.** Keep `CommercialID` and `ServiceID`; never copy another
  machine's identities.
- **A registry value is not the product.** The gate is section 0.1, not a single key.

---

## 10. Acceptance checklist

```text
[ ] Discovery sheet complete for this build
[ ] Product type = target id
[ ] RegisteredFeature = target feature
[ ] InstalledProductName = target name
[ ] About\ProductName = target name
[ ] Product ID = target id
[ ] Config = target module list, on both name keys
[ ] FeaturesController = every target feature allowed
[ ] Plugin sets = target edition, expected counts
[ ] cst_sdk_vsserv = target variant
[ ] Sub_ID DATA = target bundle, IsValid true, target features, own IDs
[ ] Ignisv2 running, firewall module loaded
[ ] UI title and Protection page match the target edition
[ ] Backup folder complete and readable
[ ] Rollback path tested or documented
[ ] No account change, no key, no subscription
```


