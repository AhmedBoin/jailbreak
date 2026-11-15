#Requires -Version 5.1
<#
    patch-ultraiso.ps1 - UltraISO Premium 9.7.6.3829 trial to retail.

    Modes
      Check    report size, SHA256, and the byte state of every patch site
      Apply    patch every site, verify the result, keep a pristine backup
      Restore  write the pristine backup back over the target and verify

    The patcher is build locked: it refuses any file that is not the shipped
    9.7.6.3829 build and any file whose patch sites are neither pristine nor
    already patched. There is no force switch and no offset that is written
    without a byte check.

    Examples
      .\patch-ultraiso.ps1 -Mode Check
      .\patch-ultraiso.ps1 -Mode Apply
      .\patch-ultraiso.ps1 -Mode Apply -Target D:\lab\UltraISO.exe -BackupDir D:\lab\backup
      .\patch-ultraiso.ps1 -Mode Restore
#>
[CmdletBinding()]
param(
    [ValidateSet('Check', 'Apply', 'Restore')]
    [string]$Mode = 'Check',

    [string]$Target,

    [string]$BackupDir = (Join-Path $env:ProgramData 'ultraiso-patch\backup'),

    [switch]$NoElevate
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$expectedSize = 5543368
$pristineHash = 'F89E9D336C6F49FBD847EA513A11BB1BFA80EA5FD1336E23CAD7D80370BAEA65'
$patchedHash = '31896FFD80D167F8B791F24C5EDAE0CAB083F2F56EE825A22D78C490B869192D'
$processName = 'UltraISO'
$versionLabel = 'UltraISO Premium 9.7.6.3829'

# VA, file offset, original bytes, patched bytes, meaning.
$sites = @(
    [pscustomobject]@{
        Name = 'licence flag, force the validate branch'
        Va = 0x403052; Offset = 0x2652
        Orig = [byte[]](0x8b, 0x15, 0xe0, 0xbe, 0x6e, 0x00)
        Patch = [byte[]](0xba, 0x01, 0x00, 0x00, 0x00, 0x90)
    },
    [pscustomobject]@{
        Name = 'validator call replaced by mov eax,1'
        Va = 0x40306A; Offset = 0x266A
        Orig = [byte[]](0xe8, 0x9d, 0xe8, 0xff, 0xff)
        Patch = [byte[]](0xb8, 0x01, 0x00, 0x00, 0x00)
    },
    [pscustomobject]@{
        Name = 'startup nag branch je to jmp'
        Va = 0x4030A8; Offset = 0x26A8
        Orig = [byte[]](0x74, 0x19)
        Patch = [byte[]](0xeb, 0x19)
    },
    [pscustomobject]@{
        Name = 'caption literal, trial to retail wording'
        Va = 0x6E7D55; Offset = 0x2E7355
        Orig = [byte[]](0x28, 0x54, 0x72, 0x69, 0x61, 0x6c, 0x20, 0x56, 0x65, 0x72, 0x73, 0x69, 0x6f, 0x6e, 0x29)
        Patch = [byte[]](0x50, 0x72, 0x65, 0x6d, 0x69, 0x75, 0x6d, 0x20, 0x45, 0x64, 0x69, 0x74, 0x69, 0x6f, 0x6e)
    }
)

function Say([string]$Message) { Write-Host $Message }
function Fail([string]$Message) {
    Write-Host ("error   : {0}" -f $Message)
    exit 1
}

function Get-Sha256([string]$Path) {
    (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
}

function Resolve-UltraisoTarget {
    if ($Target) {
        if (-not (Test-Path -LiteralPath $Target -PathType Leaf)) { Fail "target not found: $Target" }
        return (Resolve-Path -LiteralPath $Target).Path
    }
    $key = 'HKCU:\SOFTWARE\EasyBoot Systems\UltraISO\5.0'
    if (Test-Path $key) {
        $install = (Get-ItemProperty -Path $key -ErrorAction SilentlyContinue).'(default)'
        if ($install) {
            $candidate = Join-Path $install 'UltraISO.exe'
            if (Test-Path -LiteralPath $candidate -PathType Leaf) { return (Resolve-Path -LiteralPath $candidate).Path }
        }
    }
    $roots = @($env:ProgramFiles, ${env:ProgramFiles(x86)}) | Where-Object { $_ }
    foreach ($root in $roots) {
        $candidate = Join-Path $root 'UltraISO\UltraISO.exe'
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { return (Resolve-Path -LiteralPath $candidate).Path }
    }
    Fail 'UltraISO.exe not found; pass -Target'
}

function Get-SiteState([byte[]]$Bytes, $Site) {
    if ($Site.Offset + $Site.Orig.Length -gt $Bytes.Length) { return 'unknown' }
    $window = New-Object byte[] $Site.Orig.Length
    [Array]::Copy($Bytes, $Site.Offset, $window, 0, $Site.Orig.Length)
    $sameOrig = $true
    $samePatch = $true
    for ($i = 0; $i -lt $Site.Orig.Length; $i++) {
        if ($window[$i] -ne $Site.Orig[$i]) { $sameOrig = $false }
        if ($window[$i] -ne $Site.Patch[$i]) { $samePatch = $false }
    }
    if ($sameOrig) { return 'pristine' }
    if ($samePatch) { return 'patched' }
    return 'unknown'
}

function Get-Report([string]$Path) {
    $bytes = [IO.File]::ReadAllBytes($Path)
    $hash = Get-Sha256 $Path
    $states = foreach ($site in $sites) { Get-SiteState $bytes $site }
    $unknown = @($states | Where-Object { $_ -eq 'unknown' }).Count
    $patched = @($states | Where-Object { $_ -eq 'patched' }).Count
    $pristine = @($states | Where-Object { $_ -eq 'pristine' }).Count
    $overall = switch ($true) {
        ($unknown -gt 0) { 'unsupported' }
        ($patched -eq $sites.Count) { 'patched' }
        ($pristine -eq $sites.Count) { 'pristine' }
        default { 'mixed' }
    }
    [pscustomobject]@{
        Path = $Path; Size = $bytes.Length; Hash = $hash
        States = $states; Overall = $overall
    }
}

function Show-Report($Report) {
    Say ("target  : {0}" -f $Report.Path)
    Say ("version : {0} (build lock)" -f $versionLabel)
    Say ("size    : {0} (expected {1})" -f $Report.Size, $expectedSize)
    Say ("sha256  : {0}" -f $Report.Hash)
    for ($i = 0; $i -lt $sites.Count; $i++) {
        Say ("  site {0}  va 0x{1:X6}  off 0x{2:X6}  {3,-8}  {4}" -f ($i + 1), $sites[$i].Va, $sites[$i].Offset, $Report.States[$i], $sites[$i].Name)
    }
    Say ("state   : {0}" -f $Report.Overall)
}

function Assert-Blank([string]$Path) {
    $running = Get-Process -Name $processName -ErrorAction SilentlyContinue
    if ($running) { Fail ("{0} is running (pid {1}); close it and rerun" -f $processName, (($running | Select-Object -ExpandProperty Id) -join ',')) }
    $dir = Split-Path -Parent $Path
    $probe = Join-Path $dir ('.wtest-' + [guid]::NewGuid().ToString('n'))
    try {
        $stream = [IO.File]::Open($probe, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
        $stream.Close()
        Remove-Item -LiteralPath $probe -Force
    } catch [System.UnauthorizedAccessException] {
        Fail "access denied writing to $dir; rerun from an elevated shell"
    } catch {
        if (Test-Path -LiteralPath $probe) { Remove-Item -LiteralPath $probe -Force -ErrorAction SilentlyContinue }
        Fail ("cannot write to {0}: {1}" -f $dir, $_.Exception.Message)
    }
}

function Test-Elevated {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Invoke-ElevatedSelf {
    if ($NoElevate) { return $false }
    $isWindows = $true
    if ($PSVersionTable.ContainsKey('Platform')) { $isWindows = $PSVersionTable.Platform -eq 'Win32NT' }
    if (-not $isWindows) { return $false }
    if (Test-Elevated) { return $false }
    $arguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"{0}"' -f $PSCommandPath), '-Mode', $Mode, '-BackupDir', ('"{0}"' -f $BackupDir))
    if ($Target) { $arguments += @('-Target', ('"{0}"' -f $Target)) }
    try {
        Start-Process -FilePath 'powershell.exe' -ArgumentList $arguments -Verb RunAs -Wait
        return $true
    } catch {
        Fail 'elevation was refused; rerun from an elevated shell'
    }
}

function Write-Target([string]$Path, [byte[]]$Bytes, [string]$ExpectHash) {
    $dir = Split-Path -Parent $Path
    $original = Get-Item -LiteralPath $Path
    $attributes = $original.Attributes
    if ($attributes -band [IO.FileAttributes]::ReadOnly) {
        $original.Attributes = $attributes -band (-bnot [IO.FileAttributes]::ReadOnly)
    }
    $temp = Join-Path $dir ('.patch-' + [guid]::NewGuid().ToString('n') + '.tmp')
    try {
        [IO.File]::WriteAllBytes($temp, $Bytes)
        $tempHash = Get-Sha256 $temp
        if ($tempHash -ne $ExpectHash) { Fail "temp file hash mismatch: $tempHash" }
        try {
            [IO.File]::Replace($temp, $Path, $null, $true)
        } catch {
            Move-Item -LiteralPath $temp -Destination $Path -Force
        }
        $finalHash = Get-Sha256 $Path
        if ($finalHash -ne $ExpectHash) { Fail "post-write hash mismatch: $finalHash" }
    } finally {
        if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue }
        $leftover = $Path + '.replaced'
        if (Test-Path -LiteralPath $leftover) { Remove-Item -LiteralPath $leftover -Force -ErrorAction SilentlyContinue }
        try { (Get-Item -LiteralPath $Path).Attributes = $attributes } catch { }
    }
}

$targetPath = Resolve-UltraisoTarget
$report = Get-Report $targetPath

Switch ($Mode) {
    'Check' {
        Show-Report $report
        if ($report.Size -ne $expectedSize -or $report.Overall -eq 'unsupported') {
            Say 'result  : this file is not a supported build; Apply would refuse'
            exit 1
        }
        if ($report.Overall -eq 'patched' -and $report.Hash -ne $patchedHash) {
            Say 'result  : every site reads patched but the whole-file hash differs; inspect before trusting'
            exit 1
        }
        Say 'result  : supported'
        exit 0
    }
    'Apply' {
        Show-Report $report
        if ($report.Size -ne $expectedSize) { Fail "unsupported size $($report.Size); expected $expectedSize" }
        if ($report.Overall -eq 'unsupported') { Fail 'patch sites do not match any known state; refusing to write' }
        if ($report.Overall -eq 'patched') {
            if ($report.Hash -eq $patchedHash) { Say 'result  : already patched, nothing to do'; exit 0 }
            Fail "sites are patched but the file hash is $($report.Hash); refusing to guess"
        }
        if ($report.Overall -eq 'pristine' -and $report.Hash -ne $pristineHash) {
            Fail "sites are pristine but the file hash is $($report.Hash); refusing to write an unknown build"
        }
        if ($report.Overall -eq 'mixed') { Fail 'partial patch state; restore the pristine backup first' }

        if (-not (Test-Elevated) -and -not $NoElevate) {
            if (Invoke-ElevatedSelf) { exit 0 }
        }
        Assert-Blank $targetPath

        $null = New-Item -ItemType Directory -Path $BackupDir -Force
        $backupPath = Join-Path $BackupDir 'UltraISO.exe.orig'
        if (Test-Path -LiteralPath $backupPath) {
            $backupHash = Get-Sha256 $backupPath
            if ($backupHash -ne $pristineHash) { Fail "existing backup does not match the pristine hash: $backupHash" }
            Say ("backup  : reused {0}" -f $backupPath)
        } else {
            Copy-Item -LiteralPath $targetPath -Destination $backupPath -Force
            $backupHash = Get-Sha256 $backupPath
            if ($backupHash -ne $pristineHash) { Fail "backup hash mismatch: $backupHash" }
            Say ("backup  : created {0}" -f $backupPath)
        }

        $bytes = [IO.File]::ReadAllBytes($targetPath)
        $patched = [byte[]]$bytes.Clone()
        foreach ($site in $sites) {
            [Array]::Copy($site.Patch, 0, $patched, $site.Offset, $site.Patch.Length)
        }
        Write-Target $targetPath $patched $patchedHash
        $after = Get-Report $targetPath
        Show-Report $after
        if ($after.Hash -ne $patchedHash) { Fail "final hash is $($after.Hash), expected $patchedHash" }
        Say 'result  : patched and verified'
        exit 0
    }
    'Restore' {
        Show-Report $report
        $backupPath = Join-Path $BackupDir 'UltraISO.exe.orig'
        if (-not (Test-Path -LiteralPath $backupPath)) { Fail "backup not found: $backupPath" }
        $backupHash = Get-Sha256 $backupPath
        if ($backupHash -ne $pristineHash) { Fail "backup is not the pristine build: $backupHash" }
        if ($report.Hash -eq $pristineHash) { Say 'result  : already pristine, nothing to do'; exit 0 }
        if (-not (Test-Elevated) -and -not $NoElevate) {
            if (Invoke-ElevatedSelf) { exit 0 }
        }
        Assert-Blank $targetPath
        Write-Target $targetPath ([IO.File]::ReadAllBytes($backupPath)) $pristineHash
        $after = Get-Report $targetPath
        Show-Report $after
        Say ("result  : restored from {0}" -f $backupPath)
        exit 0
    }
}
