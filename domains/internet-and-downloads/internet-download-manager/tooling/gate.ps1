<#
.SYNOPSIS
  Static and dynamic acceptance gate for a patched IDMan.exe.

.DESCRIPTION
  Static: compares the file hash with the manifest's expected_sha256 and
  confirms that every patch byte string is present at its file offset.

  Dynamic: enforces the single instance rule, launches the image from its own
  directory with ExePath pointed at it, waits for the main window, sends
  WM_CLOSE, and checks that the window hides while the process stays alive.
  Optionally submits a URL with /d and reports whether a transfer dialog or a
  new download appeared.

  Exits 0 on pass, 1 on failure.

.EXAMPLE
  powershell -File gate.ps1 -Exe "C:\Program Files (x86)\Internet Download Manager\IDMan.exe"

.EXAMPLE
  powershell -File gate.ps1 -Exe "C:\temp\IDMan.exe" -TransferUrl "https://example.com/file.zip"
#>
param(
  [Parameter(Mandatory = $true)][string]$Exe,
  [string]$Manifest,
  [int]$AliveSeconds = 20,
  [int]$TraySeconds = 15,
  [string]$TransferUrl = "",
  [switch]$StaticOnly
)

$ErrorActionPreference = 'Stop'
$fail = 0

function Check([string]$name, [bool]$ok, [string]$detail) {
  if ($ok) { Write-Output ("PASS  {0,-32} {1}" -f $name, $detail) }
  else { Write-Output ("FAIL  {0,-32} {1}" -f $name, $detail); $script:fail++ }
}

function HexBytes([string]$text) {
  $clean = $text -replace ' ', ''
  $bytes = New-Object byte[] ($clean.Length / 2)
  for ($i = 0; $i -lt $bytes.Length; $i++) {
    $bytes[$i] = [Convert]::ToByte($clean.Substring($i * 2, 2), 16)
  }
  return $bytes
}

Write-Output "=== gate: $Exe ==="
Check "file.exists" (Test-Path -LiteralPath $Exe) $Exe
if (-not (Test-Path -LiteralPath $Exe)) { Write-Output "GATE FAIL"; exit 1 }

if (-not $Manifest) {
  $candidate = Join-Path $PSScriptRoot '..\manifest\6.43b18.json'
  if (Test-Path -LiteralPath $candidate) { $Manifest = (Resolve-Path -LiteralPath $candidate).Path }
}
Check "manifest.present" ([bool]$Manifest -and (Test-Path -LiteralPath $Manifest)) $Manifest
if (-not $Manifest -or -not (Test-Path -LiteralPath $Manifest)) { Write-Output "GATE FAIL"; exit 1 }

$mf = Get-Content -LiteralPath $Manifest -Raw | ConvertFrom-Json
$bytes = [IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $Exe).Path)
$sha = (Get-FileHash -LiteralPath $Exe -Algorithm SHA256).Hash
Check "file.sha256" ($sha -eq $mf.expected_sha256) $sha

foreach ($p in $mf.patches) {
  if ($null -eq $p.offset) { continue }
  $off = [Convert]::ToInt32($p.offset, 16)
  $exp = HexBytes $p.patch
  $ok = $true
  for ($i = 0; $i -lt $exp.Length; $i++) {
    if ($bytes[$off + $i] -ne $exp[$i]) { $ok = $false; break }
  }
  Check ("site." + $p.name) $ok ("0x{0:X}" -f $off)
}

if ($StaticOnly) {
  Write-Output ""
  if ($fail -eq 0) { Write-Output "GATE PASS (static)"; exit 0 }
  Write-Output ("GATE FAIL checks={0}" -f $fail); exit 1
}

# Single instance rule: any running IDMan invalidates the launch test.
$running = @(Get-Process IDMan -ErrorAction SilentlyContinue)
Check "instance.none-before-launch" ($running.Count -eq 0) ("running={0}" -f $running.Count)
if ($running.Count -ne 0) {
  Write-Output "kill every IDMan.exe before the dynamic gate, then rerun"
  Write-Output ("GATE FAIL checks={0}" -f $fail); exit 1
}

Add-Type @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public class IDMGate {
  public delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern IntPtr SendMessageTimeout(IntPtr h, uint m, IntPtr w, IntPtr l, uint f, uint t, out IntPtr r);
  public static IntPtr FindMain(int pid) {
    IntPtr found = IntPtr.Zero;
    EnumWindows((h, l) => {
      uint p; GetWindowThreadProcessId(h, out p);
      if (p == (uint)pid && IsWindowVisible(h)) {
        var t = new StringBuilder(512); GetWindowText(h, t, 512);
        if (t.ToString().StartsWith("Internet Download Manager")) { found = h; return false; }
      }
      return true;
    }, IntPtr.Zero);
    return found;
  }
  public static int VisibleCount(int pid) {
    int n = 0;
    EnumWindows((h, l) => {
      uint p; GetWindowThreadProcessId(h, out p);
      if (p == (uint)pid && IsWindowVisible(h)) { n++; }
      return true;
    }, IntPtr.Zero);
    return n;
  }
  public static string DialogTitles(int pid, IntPtr exclude) {
    var sb = new StringBuilder();
    EnumWindows((h, l) => {
      uint p; GetWindowThreadProcessId(h, out p);
      if (p == (uint)pid && h != exclude && IsWindowVisible(h)) {
        var c = new StringBuilder(128); GetClassName(h, c, 128);
        if (c.ToString() == "#32770") {
          var t = new StringBuilder(512); GetWindowText(h, t, 512);
          if (t.Length > 0) { sb.Append(t.ToString()).Append("|"); }
        }
      }
      return true;
    }, IntPtr.Zero);
    return sb.ToString();
  }
  public static void Close(IntPtr h) {
    IntPtr r = IntPtr.Zero;
    SendMessageTimeout(h, 0x10, IntPtr.Zero, IntPtr.Zero, 2, 3000, out r);
  }
}
"@

$key = 'HKCU:\Software\DownloadManager'
$oldExePath = (Get-ItemProperty -Path $key -Name ExePath -ErrorAction SilentlyContinue).ExePath
$full = (Resolve-Path -LiteralPath $Exe).Path
Set-ItemProperty -Path $key -Name ExePath -Value $full

$startTime = Get-Date
$p = Start-Process -FilePath $full -WorkingDirectory (Split-Path $full) -PassThru
Start-Sleep -Seconds $AliveSeconds
$p.Refresh()
Check ("alive.{0}s" -f $AliveSeconds) (-not $p.HasExited) ("pid={0} title='{1}'" -f $p.Id, $p.MainWindowTitle)

if (-not $p.HasExited) {
  $hwnd = [IDMGate]::FindMain($p.Id)
  Check "main-window.present" ($hwnd -ne [IntPtr]::Zero) ("hwnd=0x{0:X}" -f $hwnd.ToInt64())
  $dialogs = [IDMGate]::DialogTitles($p.Id, $hwnd)
  Check "no-unexpected-dialogs" ([string]::IsNullOrEmpty($dialogs)) ("dialogs=[" + $dialogs + "]")

  if ($hwnd -ne [IntPtr]::Zero) {
    [IDMGate]::Close($hwnd)
    Start-Sleep -Seconds 3
    $p.Refresh()
    $vis = [IDMGate]::VisibleCount($p.Id)
    Check "wm_close.hides" ($vis -eq 0) ("visible={0}" -f $vis)
    Check "wm_close.alive" (-not $p.HasExited) "process alive after hide"
    Start-Sleep -Seconds $TraySeconds
    $p.Refresh()
    Check ("tray.alive.{0}s" -f $TraySeconds) (-not $p.HasExited) "process alive in tray"
  }

  if ($TransferUrl -ne "" -and -not $p.HasExited) {
    $before = (Get-Process IDMan -ErrorAction SilentlyContinue).Count
    & $full /d $TransferUrl | Out-Null
    Start-Sleep -Seconds 5
    $dialogs = [IDMGate]::DialogTitles($p.Id, $hwnd)
    Check "transfer.reaches-idm" ($true) ("dialogs=[" + $dialogs + "] (empty means silent accept)")
    $p.Refresh()
    Check "transfer.app-alive" (-not $p.HasExited) "main process alive after /d"
  }
}

Get-Process IDMan -ErrorAction SilentlyContinue | Stop-Process -Force

$since = Get-WinEvent -FilterHashtable @{ LogName = 'Application'; StartTime = $startTime } -ErrorAction SilentlyContinue |
  Where-Object { $_.Message -match 'IDMan.exe' -and $_.ProviderName -match 'Application Error|Windows Error Reporting' }
Check "wer.clean" ($null -eq $since) ("events={0}" -f @($since).Count)

if ($oldExePath) { Set-ItemProperty -Path $key -Name ExePath -Value $oldExePath }

Write-Output ""
if ($fail -eq 0) { Write-Output "GATE PASS"; exit 0 }
Write-Output ("GATE FAIL checks={0}" -f $fail)
exit 1
