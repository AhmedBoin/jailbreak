[CmdletBinding()]
param(
    [string]$RepoRoot = ""
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
    $RepoRoot = Resolve-Path (Join-Path $scriptDir "..\..\..")
}

$failures = New-Object System.Collections.Generic.List[string]

# Build the patterns from fragments so this script does not flag itself.
$pathPatterns = @(
    ("C:" + "\Users\"),
    ("Desk" + "top\"),
    ("MTPW-13.9-crack-" + "backup")
)

$emailPatterns = @(
    ("@gmail" + ".com"),
    ("@outlook" + ".com"),
    ("@hotmail" + ".com"),
    ("@yahoo" + ".com")
)

$machinePatterns = @(
    ("ALIEN" + "WARE")
)

$textExtensions = @(
    ".md", ".txt", ".cs", ".py", ".ps1", ".cmd", ".bat",
    ".json", ".yml", ".yaml", ".svg", ".html", ".js", ".ts"
)

$rootReadme = Join-Path $RepoRoot "README.md"
$licensePath = Join-Path $RepoRoot "LICENSE"
$uncensoredPath = Join-Path $RepoRoot "Uncensored.md"
$domainsPath = Join-Path $RepoRoot "domains"

foreach ($required in @($rootReadme, $licensePath, $uncensoredPath, $domainsPath)) {
    if (-not (Test-Path $required)) {
        $failures.Add("Missing required path: $required")
    }
}

if (Test-Path $licensePath) {
    $licenseText = [System.IO.File]::ReadAllText($licensePath)
    if ($licenseText -notmatch "MIT License") {
        $failures.Add("LICENSE does not contain the MIT License header.")
    }
}

if (Test-Path $rootReadme) {
    $rootText = [System.IO.File]::ReadAllText($rootReadme)
    if ($rootText -match "domains/[a-z0-9-]+/[a-z0-9-]+") {
        $failures.Add("README.md contains a direct project link. Keep the root README generic.")
    }
}

if (Test-Path $domainsPath) {
    $projectDirs = @()
    foreach ($domainDir in Get-ChildItem $domainsPath -Directory) {
        foreach ($projectDir in Get-ChildItem $domainDir.FullName -Directory) {
            $projectDirs += $projectDir
        }
    }

    if ($projectDirs.Count -eq 0) {
        $failures.Add("domains/ contains no project folders.")
    }

    foreach ($projectDir in $projectDirs) {
        $projectReadme = Join-Path $projectDir.FullName "README.md"
        if (-not (Test-Path $projectReadme)) {
            $failures.Add("Project is missing README.md: $($projectDir.FullName)")
        }

        $playbooks = @(Get-ChildItem $projectDir.FullName -File -Filter "*playbook*.md")
        if ($playbooks.Count -eq 0) {
            $failures.Add("Project is missing a playbook: $($projectDir.FullName)")
        }
    }
}

$trackedFiles = @(git -C $RepoRoot ls-files --cached --others --exclude-standard)
if ($LASTEXITCODE -ne 0) {
    throw "git ls-files failed. Run this from a Git clone."
}

foreach ($relativePath in $trackedFiles) {
    if ([string]::IsNullOrWhiteSpace($relativePath)) { continue }

    $fullPath = Join-Path $RepoRoot $relativePath
    if (-not (Test-Path $fullPath)) { continue }

    $item = Get-Item $fullPath
    if ($item.Length -gt 20MB) {
        $failures.Add("Tracked file is larger than 20 MB: $relativePath")
    }

    $extension = [System.IO.Path]::GetExtension($relativePath).ToLowerInvariant()
    $allPatterns = @($pathPatterns + $emailPatterns + $machinePatterns)

    if ($textExtensions -contains $extension) {
        $text = [System.IO.File]::ReadAllText($fullPath)
        foreach ($pattern in $allPatterns) {
            if ($text.IndexOf($pattern, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
                $failures.Add("$relativePath contains a blocked string: $pattern")
            }
        }
    }
    else {
        $bytes = [System.IO.File]::ReadAllBytes($fullPath)
        $ascii = [System.Text.Encoding]::ASCII.GetString($bytes)
        foreach ($pattern in @($pathPatterns + $emailPatterns)) {
            if ($ascii.IndexOf($pattern, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
                $failures.Add("$relativePath contains a blocked binary string: $pattern")
            }
        }
    }
}

if ($failures.Count -gt 0) {
    Write-Host "FAIL" -ForegroundColor Red
    foreach ($failure in $failures) {
        Write-Host " - $failure" -ForegroundColor Red
    }
    exit 1
}

Write-Host "OK: repository checks passed." -ForegroundColor Green
exit 0
