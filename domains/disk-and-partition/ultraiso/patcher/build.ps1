#Requires -Version 5.1
<#
    build.ps1 - one command build for the UltraISO patcher.

    The patcher is a PowerShell script, so "build" means: parse-check it,
    stamp the output with the source hash, and copy it to dist/ as a single
    standalone file. The compiled artifact never enters the repository.

    Usage
      .\build.ps1
      .\build.ps1 -OutDir D:\build\ultraiso
#>
[CmdletBinding()]
param(
    [string]$OutDir = (Join-Path $PSScriptRoot 'dist')
)

$ErrorActionPreference = 'Stop'

$source = Join-Path $PSScriptRoot 'src\patch-ultraiso.ps1'
if (-not (Test-Path -LiteralPath $source)) { throw "source not found: $source" }

$tokens = $null
$errors = $null
$null = [System.Management.Automation.Language.Parser]::ParseFile($source, [ref]$tokens, [ref]$errors)
if ($errors -and $errors.Count -gt 0) {
    foreach ($e in $errors) { Write-Host ("parse error: {0} (line {1})" -f $e.Message, $e.Extent.StartLineNumber) }
    throw 'source does not parse'
}

$hash = (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash
$size = (Get-Item -LiteralPath $source).Length

$null = New-Item -ItemType Directory -Path $OutDir -Force
$out = Join-Path $OutDir 'patch-ultraiso.ps1'
Copy-Item -LiteralPath $source -Destination $out -Force

Write-Host ("source : {0}" -f $source)
Write-Host ("size   : {0}" -f $size)
Write-Host ("sha256 : {0}" -f $hash)
Write-Host ("output : {0}" -f $out)
Write-Host 'run    : powershell -NoProfile -ExecutionPolicy Bypass -File dist\patch-ultraiso.ps1 -Mode Check'
