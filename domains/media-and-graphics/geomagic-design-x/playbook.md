# Geomagic Design X 2026.1 Playbook

Target: Geomagic Design X 2026.1 (Hexagon)

Version: 2026.1.0.0327

Domain: media-and-graphics

Status: desktop verified on Windows 11 x64 on 2026-11-26. Offline; no `.cml`, serial, or licence server.

## 1. Target profile

- Vendor: Hexagon Manufacturing Intelligence (Geomagic).
- Install path: `C:\Program Files\Geomagic\Geomagic Design X 2026.1`.
- Launcher: `GeomagicDesignX.exe`, 317,704 bytes, image base `0x140000000`.
- UI process: `bin\RapidformMain.exe`, 7,602,440 bytes, image base `0x140000000`.
- Main licence module: `bin\rfCommonBase.dll`, 4,799,004 bytes, image base `0x180000000`.
- CimLM client: `bin\CLMnextClient.dll`, 12,533,760 bytes.
- CimLM server: `bin\CimLmServ.dll`, 16,616,592 bytes.
- Crypto: `bin\LIBEAY32.dll`, OpenSSL 1.0.2q, 2,297,456 bytes, image base `0x180000000`.
- HASP vendor DLL: `hasp_windows_x64_41472.dll`.
- Architecture: x64, PE32+.
- Framework: MFC/BCG UI, CimLM 12.
- Protector: Themida/WinLicense on `RapidformMain.exe`, `rfCommonBase.dll`, and `CimLmServ.dll`; strings include `Software\WinLicense` and `WinLicenseVersion`.
- Licence UI: Geomagic License Manager. The application displays `A valid license has not been found. To set a license, close the application and run the License Manager.`
- Licence data: `C:\ProgramData\CLM\LicFiles\GeomagicDesignX\CLMConfig.xml`. The reference install has no `.cml` file.
- Update mechanism: installer or repair replaces `bin` files. No in-app updater was observed.

## 2. Reference build

```text
GeomagicDesignX.exe              317,704
SHA256 90835A4C338A14E148C69F6E57389AB2322D1282996A9AFE3C85DB43A09B0F02

bin\RapidformMain.exe          7,602,440
SHA256 87F65D6BCC6D0277E615C039C53C174891FA028D1BE92A924B4E812CFFEFF74F
image base 0x140000000

bin\rfCommonBase.dll           4,799,004
SHA256 11BE22B433AFCA3B163E5D6A09B2920F280F498D25F8081DB2AA98B96666F47C
image base 0x180000000

bin\CLMnextClient.dll         12,533,760
SHA256 D87683D208AB89AB21F4771E52B577BAB060DF7B83019C0C6A9D6B612A8850DD

bin\CimLmServ.dll             16,616,592
SHA256 C05C24BB4815EC8B30A55457527033DDAE28D1956A4DF9F5DA745A10B5B71E1B

bin\LIBEAY32.dll (stock)       2,297,456
SHA256 E748BA7FCDAF33D219891C0311A61AEBF8546047960793159AFC0824B5D40885

bin\LIBEAY32.dll (proxy)       2,285,056
SHA256 77CE8689722D93A0871946CD6BB867A90A6A369445D321AC1788F030E451AA74

Geomagic_Design_X_patcher.dll    159,744
SHA256 E56F814168F8DF8FEF8F8BE1B31E2055C8D2488B3188A8CE0F8D4AFDDABABDCA
```

The patcher hash is from a Visual Studio 2022 17.14 x64 build. The source in section 7 is the authoritative artifact; another compiler can produce a different hash.

The gate address in section 4 is a runtime address for this exact build. The `CRFLicense` patches are resolved by export name and are not tied to the RVA values, but the export names and the function signatures must match.

## 3. Protection analysis

The application has two licence layers.

The first layer is CimLM 12. `CLMnextClient.dll` talks to `CimLmServ.dll`; the server validates a signed `.cml` container inside Themida-protected code. A locally created XML file is rejected with a version or format error, and the log records `License Error: No valid license`. The CimLM server cannot be satisfied without a validly signed licence file, and the signature is not forgeable from the client side. This layer is not the target of this playbook.

The second layer is the application's own `CRFLicense` class in `rfCommonBase.dll`. The class is exported and visible to the rest of the product:

```text
?CheckLicense@CRFLicense@@SAI_K@Z
?GetLicenseCondition@CRFLicense@@SA?AW4eLicenseCondition@@XZ
?GetLicenseType@CRFLicense@@SA_KXZ
?GetLicensePackageType@CRFLicense@@SA_KXZ
?IsProPack@CRFLicense@@SA_NXZ
?IsPlusPack@CRFLicense@@SA_NXZ
?IsGoPack@CRFLicense@@SA_NXZ
?IsEssentialsPack@CRFLicense@@SA_NXZ
?IsKeyencePack@CRFLicense@@SA_NXZ
?IsEducationalOptPack@CRFLicense@@SA_NXZ
?IsLocalValidLicenseExists@CRFLicense@@SA_NXZ
?IsFloatingValidLicenseExists@CRFLicense@@SA_NXZ
?Validate@CRFLicense@@SA_NPEAI@Z
?StartLicense@CRFLicense@@SA_N_N@Z
?CheckDateLegality@CRFLicense@@SA_NXZ
?GetExpirationDate@CRFLicense@@SA_NAEAH@Z
```

`rfDllManager.dll` imports `GetLicenseCondition` and `GetLicenseType` and uses them to decide which command modules and commands are registered. The command DLLs import `CheckLicense`; `RFFileIO.dll` and `rfXRL.dll` import the pack predicates. When those exports report no licence, the application starts with a skeleton ribbon: a few tabs and no modelling commands. This was measured with the gate patched but no `CRFLicense` patches.

`rfCommonBase.dll` is packed, but its export table is present at load time and the exported functions are reachable with `GetProcAddress` after Themida initializes the module. The functions are small state getters:

- `GetLicenseType` is `mov rax, [rip+global]; ret`.
- `GetLicenseCondition` is `mov eax, [rip+global]; ret`.
- `IsProPack` is `cmp byte ptr [rip+global], 0x10; sete al; ret`.
- `CheckLicense` reads the type global, masks it against the argument, and returns a status.

The package global at `rfCommonBase+0x1DAAA0` holds the edition byte. Observed compares: `1` for Go, `4` for Plus, `8` for another package, `0x10` for Pro. Patching the getters is more reliable than writing the global, because the licence initialization runs again and rewrites the global.

The third piece is the startup gate in `RapidformMain.exe`. It runs before the main window and before the command registry is built. The gate function starts at `0x6F590` in the unpacked image, calls the licence decision at `0x6F5D4`, and stores the result at `0x6F5DA` with `88 44 24 21` (`mov [rsp+0x21], al`). The store is the first four bytes of the patch site. The gate is Themida-virtualized around the call; the store and the following branch are normal code after unpacking.

The working combination is therefore:

1. Force the gate to success in `RapidformMain.exe`.
2. Report a valid Pro licence from the four `CRFLicense` exports in `rfCommonBase.dll`.
3. Patch the `GetInfo` null-return sites in the command modules so the partially initialized command registry does not dereference null while the full set is being built.

The CimLM log continues to record its own failure. The UI does not consult it for the ribbon once `CRFLicense` reports licensed.

## 4. Patch sites

### 4.1 RapidformMain startup gate

Reference build only. The bytes are present after Themida unpacks the image, not in the file on disk.

| Item | Value |
|---|---|
| Module | `bin\RapidformMain.exe` |
| Gate function | RVA `0x6F590` |
| Decision call | RVA `0x6F5D4` |
| Store site | RVA `0x6F5DA` |
| Original bytes at store | `88 44 24 21` |
| Replacement, 17 bytes | `B8 01 00 00 00 90 90 90 90 90 90 E9 D4 00 00 00 90` |
| Jump target | `0x6F6BE`, the success return path |

The replacement is `mov eax,1`, six NOPs, `jmp +0xD4`, one NOP. The call at `0x6F5D4` is preserved; the patch replaces the store and the following failure branch, then jumps to the success return.

### 4.2 CRFLicense exports in rfCommonBase.dll

The patcher resolves each name with `GetProcAddress`. The RVAs below are for the reference build and are used to verify that the resolved thunk lands in the expected function.

| Export | RVA | Original shape | Patch |
|---|---:|---|---|
| `?CheckLicense@CRFLicense@@SAI_K@Z` | `0x8B790` | loads the type global, `and rdx, rcx`, compares | `B8 01 00 00 00 C3` |
| `?GetLicenseCondition@CRFLicense@@SA?AW4eLicenseCondition@@XZ` | `0x769B0` | `mov eax, [rip+global]; ret` | `B8 01 00 00 00 C3` |
| `?GetLicenseType@CRFLicense@@SA_KXZ` | `0x769D0` | `mov rax, [rip+global]; ret` | `48 B8 FF FF FF FF FF FF FF FF C3` |
| `?IsProPack@CRFLicense@@SA_NXZ` | `0x8BD00` | `cmp byte ptr [rip+global], 0x10; sete al; ret` | `B0 01 C3` |

`GetLicenseType` returns all bits set. `rfDllManager` tests package masks with `and`; `-1` satisfies every package bit. `GetLicenseCondition` returns `1`, which produces the `[Not for Resale]` condition in the title. `CheckLicense` returns a non-zero status, which the command DLLs treat as licensed. `IsProPack` returns true, which selects the Pro command set and the `[Pro]` title marker.

Do not patch `IsGoPack`, `IsPlusPack`, `IsEssentialsPack`, `IsKeyencePack`, or `IsEducationalOptPack` together with `IsProPack`. That combination was measured to change the title to `[Go]` and reduce the selected edition. Only `IsProPack` is required.

### 4.3 Package global

`rfCommonBase+0x1DAAA0`, one byte:

| Value | Package |
|---:|---|
| `0x01` | Go |
| `0x04` | Plus |
| `0x08` | another package (observed compare only) |
| `0x10` | Pro |

Writing `0x10` here is an alternative to patching `IsProPack`, but the application rewrites the global during licence initialization. The getter patch is applied after the rewrite and is the method used here.

### 4.4 GetInfo stability patches

The command modules contain the sequence

```text
FF 15 ?? ?? ?? ??   call qword ptr [rip+...]
8B 58 08            mov ebx, [rax+8]
```

When the command registry is being built with a synthetic licence, the call can return null and the following load crashes. The patcher rewrites the load to `31 DB 90` (`xor ebx, ebx; nop`) at these sites:

| Module | Sites in reference build |
|---|---:|
| `rfCmdFileIO.dll` | 4 |
| `rfCmdMeasure.dll` | 3 |
| `rfCmdRefGeom.dll` | 6 |
| `rfCmdUtility.dll` | 15 |
| `rfCmdView.dll` | 12 |
| `RFQualityChecker.dll` | 1 |
| `RFViewPoint.dll` | 4 |
| `rfNX8IFServer.dll` | 1 |
| `rfPrtWKBrepAlgorithm.dll` | 1 |
| `spkernel.dll` | 1 |

The patcher applies these at module load and again after the gate. They are not licence checks; they keep the registry build alive.

## 5. Finding the sites in a new version

### 5.1 The CRFLicense exports

The decorated names are in the export table of `rfCommonBase.dll` even when the file is packed:

```text
dumpbin /exports "bin\rfCommonBase.dll" | findstr CRFLicense
```

`GetProcAddress` resolves them at runtime. Confirm the resolved addresses against the disassembly shapes:

- `IsProPack`: `80 3D ?? ?? ?? ?? 10 0F 94 C0 C3` (`cmp byte ptr [rip+disp], 0x10; sete al; ret`).
- `GetLicenseType`: `48 8B 05 ?? ?? ?? ?? C3`.
- `GetLicenseCondition`: `8B 05 ?? ?? ?? ?? C3`.
- `CheckLicense`: `48 8B 05 ?? ?? ?? ?? 48 89 C2 48 21 CA ...` followed by the type test.

If the names change, dump the unpacked module from a running process and search the strings `CRFLicense`, `GetLicenseType`, `m_ullLicenseType`, and `m_ullAvailablePackage`. The class and the edition values have been stable across the 2024 and 2026 releases.

### 5.2 The startup gate

The gate is only visible after Themida unpacks `RapidformMain.exe`. Attach at about 1.3 seconds after process start, before the licence check runs, and scan for the store:

```javascript
const m = Process.findModuleByName('RapidformMain.exe');
const hits = Memory.scanSync(m.base, m.size, '88 44 24 21');
hits.forEach(h => console.log(h.address.sub(m.base)));
```

For the reference build the correct hit is `0x6F5DA`. Do not patch the first hit blindly. Verify each candidate:

- The four bytes are followed by the failure branch.
- Six bytes before the store is the call at `0x6F5D4` (`E8` plus a relative displacement).
- The gate function starts near `0x6F590` and the success return is at `0x6F6BE`.
- The surrounding code references the licence error path.

A second discovery path is the licence error message. The application builds `A valid license has not been found...` from the message table; the xref to that path reaches the same gate. The store signature is the final confirmation.

The patcher waits for `88 44 24 21` at `base+0x6F5DA` for up to 20 seconds. For a different build, change the offset and re-verify the signature; never apply the 17-byte replacement to an unverified site.

### 5.3 The package global

`IsProPack` contains a RIP-relative compare against `rfCommonBase+0x1DAAA0` in the reference build. In a new build, read the displacement from the `cmp` instruction and confirm the compared values (`1`, `4`, `8`, `0x10`). The Pro value is `0x10`.

## 6. Delivery through the LIBEAY32 proxy

`RapidformMain.exe` loads `bin\LIBEAY32.dll` during startup; `SSLEAY32.dll` and `cpprest141_2_10.dll` import it. A proxy `LIBEAY32.dll` that adds one static import loads the patcher without a launcher, a shortcut change, or an injection step.

The 2024 RuntimePatcher project at `https://github.com/sl4v3k/Geomagic_Design_X` contains exactly such a proxy:

```text
https://raw.githubusercontent.com/sl4v3k/Geomagic_Design_X/main/2024.3.2/RuntimePatcher/LIBEAY32.dll
SHA256 77CE8689722D93A0871946CD6BB867A90A6A369445D321AC1788F030E451AA74
```

Compatibility with the 2026 build was measured, not assumed:

- Stock 2026 `LIBEAY32.dll`: 2,297,456 bytes, SHA256 `E748BA7F...`.
- Proxy: 2,285,056 bytes, SHA256 `77CE8689...`.
- Both files have 3,709 exports.
- The `.text`, `.rdata`, `.data`, `.pdata`, and `.rsrc` sections have identical SHA256 in both files. Only `.reloc` differs, because the proxy has an additional import.
- The proxy imports `Geomagic_Design_X_patcher.dll!my_export`.

The patcher exports `my_export` with `__declspec(dllexport)`. The import resolves when the proxy loads, and the patcher's `DllMain` starts its worker. The worker checks that the host process is `RapidformMain.exe`; other processes that load the same OpenSSL copy are left untouched.

If the proxy is unavailable, any startup-loaded DLL that imports `Geomagic_Design_X_patcher.dll!my_export` works. A copy of the stock `LIBEAY32.dll` with that import added by an import editor is equivalent. Keep the section contents identical and add only the import.

Alternative delivery: a small launcher can start `GeomagicDesignX.exe` and inject `Geomagic_Design_X_patcher.dll` into `RapidformMain.exe`. That avoids modifying `bin` but requires the launcher to be used instead of the original shortcut. The proxy method is the one documented here because the original executable and shortcut keep working.

## 7. Patcher source

Save this as `gdxcrack.c`. The default licence mask is `0x87`: `CheckLicense`, `GetLicenseCondition`, `GetLicenseType`, and `IsProPack`. The environment variable `GDX_LIC_MASK` overrides it for experiments.

```c
#include <windows.h>
#include <psapi.h>
#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>

#pragma comment(lib, "psapi.lib")

__declspec(dllexport) void my_export(void) {}

static int is_target_process(void)
{
    char path[MAX_PATH] = { 0 };
    if (!GetModuleFileNameA(NULL, path, MAX_PATH)) return 0;
    const char* base = strrchr(path, '\\');
    base = base ? base + 1 : path;
    return _stricmp(base, "RapidformMain.exe") == 0;
}

static FILE* g_log = NULL;
static CRITICAL_SECTION g_cs;

static void logline(const char* fmt, ...)
{
    if (!g_log) return;
    EnterCriticalSection(&g_cs);
    va_list ap;
    va_start(ap, fmt);
    vfprintf(g_log, fmt, ap);
    va_end(ap);
    fputc('\n', g_log);
    fflush(g_log);
    LeaveCriticalSection(&g_cs);
}

static int patch_bytes(void* addr, const unsigned char* data, SIZE_T len)
{
    DWORD oldp = 0;
    if (!VirtualProtect(addr, len, PAGE_EXECUTE_READWRITE, &oldp))
        return 0;
    memcpy(addr, data, len);
    VirtualProtect(addr, len, oldp, &oldp);
    FlushInstructionCache(GetCurrentProcess(), addr, len);
    return 1;
}

static const wchar_t* kModules[] = {
    L"rfCmdFileIO.dll", L"rfCmdMeasure.dll", L"rfCmdRefGeom.dll", L"rfCmdUtility.dll",
    L"rfCmdView.dll", L"RFQualityChecker.dll", L"RFViewPoint.dll", L"rfNX8IFServer.dll",
    L"rfPrtWKBrepAlgorithm.dll", L"spkernel.dll", NULL
};

static int known_module(const wchar_t* name)
{
    for (int i = 0; kModules[i]; i++)
        if (_wcsicmp(name, kModules[i]) == 0) return 1;
    return 0;
}

static int patch_image(unsigned char* base, SIZE_T size)
{
    if (!base || size < 0x1000) return 0;
    IMAGE_DOS_HEADER* dos = (IMAGE_DOS_HEADER*)base;
    if (dos->e_magic != IMAGE_DOS_SIGNATURE) return 0;
    if ((SIZE_T)dos->e_lfanew + sizeof(IMAGE_NT_HEADERS) > size) return 0;
    IMAGE_NT_HEADERS* nt = (IMAGE_NT_HEADERS*)(base + dos->e_lfanew);
    if (nt->Signature != IMAGE_NT_SIGNATURE) return 0;
    int hits = 0;
    IMAGE_SECTION_HEADER* sec = IMAGE_FIRST_SECTION(nt);
    for (int s = 0; s < nt->FileHeader.NumberOfSections; s++, sec++) {
        if (!(sec->Characteristics & IMAGE_SCN_MEM_EXECUTE)) continue;
        SIZE_T off = sec->VirtualAddress;
        SIZE_T sz = sec->Misc.VirtualSize ? sec->Misc.VirtualSize : sec->SizeOfRawData;
        if (off + sz > size) sz = size - off;
        unsigned char* p = base + off;
        for (SIZE_T i = 0; i + 8 < sz; i++) {
            if (p[i] == 0xFF && p[i + 1] == 0x15 && p[i + 6] == 0x8B &&
                p[i + 7] == 0x58 && p[i + 8] == 0x08) {
                if (patch_bytes(p + i + 6, (const unsigned char*)"\x31\xDB\x90", 3))
                    hits++;
            }
        }
    }
    return hits;
}

static void patch_loaded(void)
{
    for (int i = 0; kModules[i]; i++) {
        HMODULE m = GetModuleHandleW(kModules[i]);
        if (!m) continue;
        int n = patch_image((unsigned char*)m, 0x40000000);
        if (n) logline("getinfo %ls: %d", kModules[i], n);
    }
}

typedef struct { USHORT Length; USHORT MaximumLength; PWSTR Buffer; } USTR;
typedef struct {
    ULONG Flags;
    USTR* FullDllName;
    USTR* BaseDllName;
    PVOID DllBase;
    ULONG SizeOfImage;
} LOADED_NOTIFY;

typedef VOID (CALLBACK *PLDR_DLL_NOTIFICATION_FUNCTION)(ULONG, const LOADED_NOTIFY*, PVOID);
typedef NTSTATUS (NTAPI *pLdrRegisterDllNotification)(ULONG, PLDR_DLL_NOTIFICATION_FUNCTION, PVOID, PVOID*);

static VOID CALLBACK dll_notify(ULONG reason, const LOADED_NOTIFY* data, PVOID ctx)
{
    (void)ctx;
    if (reason != 1 || !data || !data->BaseDllName || !data->BaseDllName->Buffer) return;
    if (!known_module(data->BaseDllName->Buffer)) return;
    int n = patch_image((unsigned char*)data->DllBase, data->SizeOfImage);
    if (n) logline("getinfo (load) %ls: %d", data->BaseDllName->Buffer, n);
}

static void patch_export_bool(const char* modname, const char* expname, int val)
{
    HMODULE m = GetModuleHandleA(modname);
    if (!m) { logline("no module %s", modname); return; }
    unsigned char* p = (unsigned char*)GetProcAddress(m, expname);
    if (!p) { logline("no export %s!%s", modname, expname); return; }
    unsigned char code[6] = { 0xB8, (unsigned char)val, 0, 0, 0, 0xC3 };
    patch_bytes(p, code, 6);
    logline("patched %s!%s = %d", modname, expname, val);
}

static void patch_clm(void)
{
    patch_export_bool("CLMnextClient.dll", "CLM_GetApiLicenseLevel", 4);
    patch_export_bool("CLMnextClient.dll", "CLM_IsLicensed", 1);
    patch_export_bool("CLMnextClient.dll", "CLM_IsLicensedEx", 1);
    patch_export_bool("CLMnextClient.dll", "CLM_LicenseMgrReady", 1);
    patch_export_bool("CLMnextClient.dll", "CLM_IsLicenseLoaded", 1);
    patch_export_bool("CLMnextClient.dll", "CLM_IsLicenseLoadedEx", 1);
    patch_export_bool("CLMnextClient.dll", "CLM_QueryFeatureFailed", 0);
    patch_export_bool("LgsxSdk.dll", "Lgsx_IsLicensed", 1);
}

/* CRFLicense export patches. The mask bits are documented in section 4. */
static const unsigned char LIC_BOOL_TRUE[] = { 0xB0, 0x01, 0xC3 };
static const unsigned char LIC_UINT_1[]    = { 0xB8, 0x01, 0x00, 0x00, 0x00, 0xC3 };
static const unsigned char LIC_ALL[]       = { 0x48, 0xB8, 0xFF, 0xFF, 0xFF, 0xFF,
                                               0xFF, 0xFF, 0xFF, 0xFF, 0xC3 };
static const unsigned char LIC_PRO[]       = { 0x48, 0xB8, 0x10, 0x00, 0x00, 0x00,
                                               0x00, 0x00, 0x00, 0x00, 0xC3 };

static int patch_one_export(HMODULE mod, const char* name,
                            const unsigned char* code, SIZE_T len)
{
    void* p = GetProcAddress(mod, name);
    if (!p) { logline("licence export missing: %s", name); return 0; }
    int ok = patch_bytes(p, code, len);
    logline("licence %s @%p -> %s", name, p, ok ? "ok" : "FAIL");
    return ok;
}

static void patch_licence(void)
{
    HMODULE mod = NULL;
    for (int i = 0; i < 20000; i++) {
        mod = GetModuleHandleW(L"rfCommonBase.dll");
        if (mod) break;
        Sleep(1);
    }
    if (!mod) { logline("rfCommonBase not loaded"); return; }

    unsigned mask = 0x87;
    char mbuf[32] = { 0 };
    if (GetEnvironmentVariableA("GDX_LIC_MASK", mbuf, sizeof(mbuf)))
        mask = (unsigned)strtoul(mbuf, NULL, 16);
    logline("rfCommonBase=%p licence mask=%08X", mod, mask);

    if (mask & 0x001) patch_one_export(mod, "?CheckLicense@CRFLicense@@SAI_K@Z", LIC_UINT_1, sizeof(LIC_UINT_1));
    if (mask & 0x002) patch_one_export(mod, "?GetLicenseCondition@CRFLicense@@SA?AW4eLicenseCondition@@XZ", LIC_UINT_1, sizeof(LIC_UINT_1));
    if (mask & 0x004) patch_one_export(mod, "?GetLicenseType@CRFLicense@@SA_KXZ", LIC_ALL, sizeof(LIC_ALL));
    if (mask & 0x008) patch_one_export(mod, "?GetLicensePackageType@CRFLicense@@SA_KXZ", LIC_PRO, sizeof(LIC_PRO));
    if (mask & 0x010) patch_one_export(mod, "?Validate@CRFLicense@@SA_NPEAI@Z", LIC_BOOL_TRUE, sizeof(LIC_BOOL_TRUE));
    if (mask & 0x020) patch_one_export(mod, "?StartLicense@CRFLicense@@SA_N_N@Z", LIC_BOOL_TRUE, sizeof(LIC_BOOL_TRUE));
    if (mask & 0x040) patch_one_export(mod, "?CheckDateLegality@CRFLicense@@SA_NXZ", LIC_BOOL_TRUE, sizeof(LIC_BOOL_TRUE));
    if (mask & 0x080) patch_one_export(mod, "?IsProPack@CRFLicense@@SA_NXZ", LIC_BOOL_TRUE, sizeof(LIC_BOOL_TRUE));
    if (mask & 0x100) patch_one_export(mod, "?IsPlusPack@CRFLicense@@SA_NXZ", LIC_BOOL_TRUE, sizeof(LIC_BOOL_TRUE));
    if (mask & 0x200) patch_one_export(mod, "?IsGoPack@CRFLicense@@SA_NXZ", LIC_BOOL_TRUE, sizeof(LIC_BOOL_TRUE));
    if (mask & 0x400) patch_one_export(mod, "?IsEssentialsPack@CRFLicense@@SA_NXZ", LIC_BOOL_TRUE, sizeof(LIC_BOOL_TRUE));
    if (mask & 0x800) patch_one_export(mod, "?IsKeyencePack@CRFLicense@@SA_NXZ", LIC_BOOL_TRUE, sizeof(LIC_BOOL_TRUE));
    if (mask & 0x1000) patch_one_export(mod, "?IsEducationalOptPack@CRFLicense@@SA_NXZ", LIC_BOOL_TRUE, sizeof(LIC_BOOL_TRUE));
    if (mask & 0x2000) patch_one_export(mod, "?IsLocalValidLicenseExists@CRFLicense@@SA_NXZ", LIC_BOOL_TRUE, sizeof(LIC_BOOL_TRUE));
    if (mask & 0x4000) patch_one_export(mod, "?IsFloatingValidLicenseExists@CRFLicense@@SA_NXZ", LIC_BOOL_TRUE, sizeof(LIC_BOOL_TRUE));
}

static DWORD WINAPI worker(LPVOID param)
{
    (void)param;
    patch_loaded();
    patch_licence();

    HMODULE app = GetModuleHandleA(NULL);
    /* Reference build 2026.1.0.0327 only. Re-locate for another build. */
    unsigned char* gate = (unsigned char*)app + 0x6F5DA;
    const unsigned char want[4] = { 0x88, 0x44, 0x24, 0x21 };
    const unsigned char repl[17] = {
        0xB8, 0x01, 0x00, 0x00, 0x00,
        0x90, 0x90, 0x90, 0x90, 0x90,
        0x90,
        0xE9, 0xD4, 0x00, 0x00, 0x00,
        0x90
    };
    for (int i = 0; i < 20000; i++) {
        if (memcmp(gate, want, 4) == 0) {
            patch_bytes(gate, repl, sizeof(repl));
            logline("gate patched at %p", gate);
            break;
        }
        Sleep(1);
    }
    patch_loaded();
    patch_licence();

    /* After the gate, advertise a full API licence level. */
    patch_export_bool("CLMnextClient.dll", "CLM_GetApiLicenseLevel", 100);
    return 0;
}

BOOL WINAPI DllMain(HINSTANCE h, DWORD reason, LPVOID r)
{
    if (reason == DLL_PROCESS_ATTACH) {
        DisableThreadLibraryCalls(h);
        if (!is_target_process()) return TRUE;
        InitializeCriticalSection(&g_cs);
        char path[MAX_PATH];
        DWORD n = GetEnvironmentVariableA("GDXCRACK_LOG", path, MAX_PATH);
        if (n == 0) {
            GetTempPathA(MAX_PATH, path);
            lstrcatA(path, "gdxcrack.log");
        }
        g_log = fopen(path, "a");
        logline("=== gdxcrack2 pid=%lu", GetCurrentProcessId());

        HMODULE ntdll = GetModuleHandleW(L"ntdll.dll");
        pLdrRegisterDllNotification reg = (pLdrRegisterDllNotification)GetProcAddress(ntdll, "LdrRegisterDllNotification");
        PVOID cookie = NULL;
        if (reg) reg(0, dll_notify, NULL, &cookie);
        CreateThread(NULL, 0, worker, NULL, 0, NULL);
    }
    return TRUE;
}
```

## 8. Build

Use an x64 Visual Studio 2022 developer prompt:

```text
call "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvars64.bat"
cl /nologo /LD /O2 /MT gdxcrack.c /link /OUT:Geomagic_Design_X_patcher.dll psapi.lib
```

The `/MT` runtime keeps the DLL independent of a redistributable. `psapi.lib` is the only non-default import library. The DLL must export `my_export`; the source does this with `__declspec(dllexport)`.

The reference build produces a 159,744-byte DLL with SHA256 `E56F814168F8DF8FEF8F8BE1B31E2055C8D2488B3188A8CE0F8D4AFDDABABDCA`.

## 9. Install and verify

As administrator, with the application closed:

```text
set "GDX=C:\Program Files\Geomagic\Geomagic Design X 2026.1"
copy /Y "%GDX%\bin\LIBEAY32.dll" "%GDX%\bin\LIBEAY32.dll.gdxbak"
copy /Y LIBEAY32.dll "%GDX%\bin\LIBEAY32.dll"
copy /Y Geomagic_Design_X_patcher.dll "%GDX%\bin\Geomagic_Design_X_patcher.dll"
start "" "%GDX%\GeomagicDesignX.exe"
```

Verification:

- The window title is `Geomagic Design X 2026. 1. 0 [Pro] [Not for Resale]`.
- The ribbon contains HOME, LIVECAPTURE, POINTS, POLYGONS, REGION, TEXTURE, ALIGNMENT, SKETCH, 3D SKETCH, MODEL, and EXACT SURFACING.
- The MODEL tab contains the solid, surface, wizard, curve, and edit commands; the HOME tab contains SOLIDWORKS LiveTransfer.
- `C:\ProgramData\CLM\LicFiles\GeomagicDesignX` contains `CLMConfig.xml` and `CimLmLib.log`; there is no `.cml`.
- `CimLmLib.log` still records `License Error: No valid license`. The UI is unaffected.
- `%TEMP%\gdxcrack.log` contains lines in this shape:

```text
=== gdxcrack2 pid=...
getinfo rfCmdFileIO.dll: 4
rfCommonBase=... licence mask=00000087
licence ?CheckLicense@CRFLicense@@SAI_K@Z @... -> ok
licence ?GetLicenseCondition@CRFLicense@@SA?AW4eLicenseCondition@@XZ @... -> ok
licence ?GetLicenseType@CRFLicense@@SA_KXZ @... -> ok
licence ?IsProPack@CRFLicense@@SA_NXZ @... -> ok
gate patched at ...
patched CLMnextClient.dll!CLM_GetApiLicenseLevel = 100
```

- The process stays responsive for more than two minutes; open the MODEL tab and confirm the commands are enabled.

## 10. Rollback

Close the application, then:

```text
set "GDX=C:\Program Files\Geomagic\Geomagic Design X 2026.1"
copy /Y "%GDX%\bin\LIBEAY32.dll.gdxbak" "%GDX%\bin\LIBEAY32.dll"
del "%GDX%\bin\Geomagic_Design_X_patcher.dll"
```

Verify the restored file:

```text
certutil -hashfile "%GDX%\bin\LIBEAY32.dll" SHA256
```

Expected: `E748BA7FCDAF33D219891C0311A61AEBF8546047960793159AFC0824B5D40885`.

The backup is the only modified file. `RapidformMain.exe` and `rfCommonBase.dll` are never written; all gate and licence patches are in memory.

## 11. Verification matrix

| Check | Expected |
|---|---|
| Title bar | `[Pro] [Not for Resale]` |
| Ribbon tabs | HOME through EXACT SURFACING, all ten |
| MODEL commands | solid, surface, wizard, curve, edit sets present |
| HOME commands | Import, Scan, LiveTransfer (SOLIDWORKS), Tools |
| Licence folder | no `.cml`; only `CLMConfig.xml` and `CimLmLib.log` |
| CimLM log | still records the no-licence error |
| Patcher log | four `licence ... -> ok` lines and `gate patched` |
| Stability | responsive for more than two minutes |
| Rollback hash | `E748BA7F...` |

## 12. Notes and limits

- The gate RVA `0x6F5DA` is specific to build 2026.1.0.0327. The patcher verifies `88 44 24 21` before writing; if the signature is absent it waits 20 seconds and does nothing. Locate the site again for another build using section 5.2.
- The `CRFLicense` patches are name-based and survive ASLR. The RVAs in section 4 are for verification, not for hardcoding.
- Patching every `Is*Pack` predicate turns the title into `[Go]`. Use only `IsProPack`.
- The gate patch alone produces a skeleton ribbon. The four `CRFLicense` patches are what populate the command registry.
- A dummy or forged `.cml` does not work. The CimLM server validates the signature inside Themida; the UI layer is patched instead.
- The LIBEAY32 proxy is loaded by other processes that use the same OpenSSL copy. The patcher exits immediately unless the host process is `RapidformMain.exe`.
- An application update or repair replaces `bin\LIBEAY32.dll` and removes the patch. Delete the stale `.gdxbak`, reinstall, and refresh the backup.
- The proxy and patcher are unsigned. Antivirus or SmartScreen may flag them; allow them if prompted.
- The 2024 RuntimePatcher is the source of the proxy. Its trial, HWID, clock, and expiry offsets are for 2024.3.2 and are not used here.
- No binary, proxy, patcher, installer, licence file, or application file is published with this playbook.
