[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Domain,

    [Parameter(Mandatory = $true)]
    [string]$Project,

    [Parameter(Mandatory = $true)]
    [string]$Title,

    [string]$Version = "1.0",

    [string]$Summary = "",

    [switch]$Force
)

$ErrorActionPreference = "Stop"

function Test-Slug([string]$Value, [string]$Name) {
    if ($Value -notmatch '^[a-z0-9][a-z0-9-]*$') {
        throw "$Name must be lowercase letters, digits, and hyphens, and must start with a letter or digit."
    }
}

Test-Slug $Domain "Domain"
Test-Slug $Project "Project"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Resolve-Path (Join-Path $scriptDir "..\..\..")
$templateDir = Join-Path $repoRoot "skills\add-crack\references"
$targetDir = Join-Path $repoRoot "domains\$Domain\$Project"

if (-not (Test-Path (Join-Path $repoRoot "domains"))) {
    throw "Run this from a Jailbreak repository clone. domains/ was not found."
}

if ((Test-Path $targetDir) -and -not $Force) {
    throw "Target already exists: $targetDir. Use -Force to overwrite the two template files."
}

New-Item -ItemType Directory -Force -Path $targetDir | Out-Null

$tokens = @{
    "{{TITLE}}"   = $Title
    "{{DOMAIN}}"  = $Domain
    "{{PROJECT}}" = $Project
    "{{VERSION}}" = $Version
    "{{SUMMARY}}" = $Summary
}

function Write-Template([string]$TemplateName, [string]$OutputName) {
    $templatePath = Join-Path $templateDir $TemplateName
    $text = [System.IO.File]::ReadAllText($templatePath)
    foreach ($key in $tokens.Keys) {
        $text = $text.Replace($key, $tokens[$key])
    }
    $outputPath = Join-Path $targetDir $OutputName
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($outputPath, $text, $utf8)
    Write-Host "created $outputPath"
}

Write-Template "project-readme-template.md" "README.md"
Write-Template "playbook-template.md" "playbook.md"

Write-Host ""
Write-Host "Project scaffolded at: $targetDir"
Write-Host ""
Write-Host "Next:"
Write-Host "  1. Fill README.md and playbook.md with the target data."
Write-Host "  2. Add patcher/ and legacy/ only when they contain files."
Write-Host "  3. Run: powershell -ExecutionPolicy Bypass -File skills/add-crack/scripts/check-repo.ps1"
Write-Host "  4. Commit and push."
