[CmdletBinding()]
param(
  [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$repoRoot = (& git rev-parse --show-toplevel 2>$null)
if ($LASTEXITCODE -ne 0 -or -not $repoRoot) {
  throw 'Open this task from the website Git repository.'
}
$repoRoot = [System.IO.Path]::GetFullPath($repoRoot.Trim()).TrimEnd([char[]]@('\', '/'))
Set-Location $repoRoot

$remote = (& git remote get-url origin 2>$null)
if ($LASTEXITCODE -ne 0 -or $remote -notmatch 'github\.com[:/]stutallica-byte/Preloved-little-pages(?:\.git)?$') {
  throw 'The origin remote must point to stutallica-byte/Preloved-little-pages.'
}
if ($remote -match '^https?://[^/]*@') {
  throw 'Remove credentials embedded in the origin URL and use Git Credential Manager or SSH.'
}

$branch = (& git branch --show-current 2>$null)
if ($LASTEXITCODE -ne 0 -or $branch.Trim() -ne 'main') {
  throw 'Switch to the main branch before publishing.'
}

foreach ($key in @('user.name', 'user.email')) {
  $value = (& git config --get $key 2>$null)
  if ($LASTEXITCODE -ne 0 -or -not $value) {
    throw "Git $key is not configured. Set it before publishing."
  }
}

function Test-GitIgnored {
  param([string]$Path)

  & git check-ignore -q --no-index -- $Path 2>$null
  return ($LASTEXITCODE -eq 0)
}

foreach ($path in @('.env', '.env.local', '.dev.vars', '.wrangler/state', 'node_modules/.publish-check', '.ssh/id_ed25519', 'publish-check.pem', 'publish-check.key')) {
  if (-not (Test-GitIgnored $path)) {
    throw "Required secret/dependency ignore rule is missing for: $path"
  }
}

function Test-SensitivePath {
  param([string]$Path)

  $segments = $Path.Replace('\', '/').Split('/')
  foreach ($segment in $segments) {
    $name = $segment.ToLowerInvariant()
    if ($name -eq '.env' -or ($name.StartsWith('.env.') -and $name -ne '.env.example')) { return $true }
    if ($name -eq '.dev.vars' -or ($name.StartsWith('.dev.vars.') -and $name -ne '.dev.vars.example')) { return $true }
    if ($name -in @('node_modules', '.wrangler', '.ssh')) { return $true }
    if ($name -match '^(id_rsa|id_dsa|id_ecdsa|id_ed25519|.+\.(pem|key|p12|pfx))$') { return $true }
  }

  return $false
}

$secretPatterns = @(
  '(?i)sb_secret_[A-Za-z0-9_-]{16,}',
  '(?i)SUPABASE_(SERVICE_ROLE|SECRET)_KEY\s*=\s*\S+',
  '-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----',
  '\bAKIA[0-9A-Z]{16}\b',
  '\bgh[pousr]_[A-Za-z0-9_]{20,}\b',
  '\bgithub_pat_[A-Za-z0-9_]{20,}\b',
  '\bsk_(live|test)_[A-Za-z0-9]{16,}\b',
  '\bxox[baprs]-[A-Za-z0-9-]{15,}\b',
  '\bAIza[0-9A-Za-z_-]{30,}\b',
  '(?i)(password|passwd|secret|token|api[_-]?key)\s*[:=]\s*"[^"\r\n]{8,}"',
  "(?i)(password|passwd|secret|token|api[_-]?key)\s*[:=]\s*'[^'\r\n]{8,}'"
)
$jwtPattern = [regex]'eyJ[A-Za-z0-9_-]{8,}\.([A-Za-z0-9_-]{8,})\.[A-Za-z0-9_-]{8,}'
$binaryExtensions = @('.avif', '.gif', '.ico', '.jpeg', '.jpg', '.pdf', '.png', '.webp', '.woff', '.woff2', '.zip')

function Test-SecretContent {
  param([string]$Content)

  foreach ($pattern in $secretPatterns) {
    if ([regex]::IsMatch($Content, $pattern)) { return $true }
  }

  foreach ($match in $jwtPattern.Matches($Content)) {
    $payload = $match.Groups[1].Value.Replace('-', '+').Replace('_', '/')
    switch ($payload.Length % 4) {
      2 { $payload += '==' }
      3 { $payload += '=' }
      1 { continue }
    }

    try {
      $json = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($payload))
    } catch [System.FormatException] {
      continue
    }
    if ($json -match '"role"\s*:\s*"service_role"') { return $true }
  }

  return $false
}

function Test-BinaryPath {
  param([string]$Path)

  $extension = [System.IO.Path]::GetExtension($Path).ToLowerInvariant()
  return $extension -in $binaryExtensions
}

function Test-WorkingFileForSecrets {
  param([string]$Path)

  if (Test-BinaryPath $Path) { return $false }
  $fullPath = [System.IO.Path]::GetFullPath((Join-Path $repoRoot $Path))
  $rootPrefix = $repoRoot.TrimEnd('\') + '\'
  if (-not $fullPath.StartsWith($rootPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Changed path resolves outside the repository: $Path"
  }
  if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) { return $false }

  try {
    $content = [System.Text.Encoding]::UTF8.GetString([System.IO.File]::ReadAllBytes($fullPath))
  } catch [System.IO.IOException] {
    throw "Could not safely scan changed file: $Path"
  } catch [System.UnauthorizedAccessException] {
    throw "Could not safely scan changed file: $Path"
  } catch [System.Security.SecurityException] {
    throw "Could not safely scan changed file: $Path"
  }
  return Test-SecretContent $content
}

function Test-IndexForSecrets {
  param([string[]]$Paths)

  foreach ($path in $Paths) {
    if ((Test-SensitivePath $path) -or (Test-BinaryPath $path)) { continue }
    $content = & git show ":$path" 2>$null
    if ($LASTEXITCODE -ne 0) { throw "Could not scan the staged file: $path" }
    if (Test-SecretContent ($content -join "`n")) { return $path }
  }

  return $null
}

$trackedPaths = @(& git ls-files)
if ($LASTEXITCODE -ne 0) { throw 'Could not inspect tracked files.' }
$trackedSensitive = @($trackedPaths | Where-Object { Test-SensitivePath $_ })
if ($trackedSensitive.Count -gt 0) {
  throw "Sensitive paths are already tracked by Git: $($trackedSensitive -join ', ')"
}

$changedPaths = @()
$changedPaths += @(& git diff --name-only --no-renames)
if ($LASTEXITCODE -ne 0) { throw 'Could not inspect unstaged changes.' }
$changedPaths += @(& git diff --cached --name-only --no-renames)
if ($LASTEXITCODE -ne 0) { throw 'Could not inspect staged changes.' }
$changedPaths += @(& git ls-files --others --exclude-standard)
if ($LASTEXITCODE -ne 0) { throw 'Could not inspect untracked files.' }
$changedPaths = @($changedPaths | Where-Object { $_ } | Sort-Object -Unique)

if ($changedPaths.Count -eq 0) {
  Write-Host 'No website changes to publish.'
  exit 0
}

Write-Host 'Files detected for review:'
foreach ($path in $changedPaths) {
  Write-Host "  $path"
  if (Test-SensitivePath $path) {
    throw "Sensitive file path is blocked from publishing: $path"
  }
}

$indexSecret = Test-IndexForSecrets $trackedPaths
if ($indexSecret) { throw "A likely secret was found in the Git index: $indexSecret" }
foreach ($path in $changedPaths) {
  if (Test-WorkingFileForSecrets $path) {
    throw "A likely secret was found in: $path. Remove it before publishing."
  }
}

if ($DryRun) {
  Write-Host 'Dry run complete. Nothing was staged, committed, or pushed.'
  exit 0
}

& git add -A
if ($LASTEXITCODE -ne 0) { throw 'Git could not stage the changes.' }

$stagedPaths = @(& git diff --cached --name-only --no-renames)
if ($LASTEXITCODE -ne 0) { throw 'Could not inspect staged changes.' }
if ($stagedPaths.Count -eq 0) {
  Write-Host 'No non-ignored changes were staged.'
  exit 0
}

$stagedSensitive = @($stagedPaths | Where-Object { Test-SensitivePath $_ })
if ($stagedSensitive.Count -gt 0) {
  throw "Sensitive paths were staged and are blocked: $($stagedSensitive -join ', ')"
}
$trackedPaths = @(& git ls-files)
if ($LASTEXITCODE -ne 0) { throw 'Could not inspect staged files.' }
$indexSecret = Test-IndexForSecrets $trackedPaths
if ($indexSecret) { throw "A likely secret was found in the staged file: $indexSecret" }

& git diff --cached --check
if ($LASTEXITCODE -ne 0) { throw 'The staged changes failed git diff --check.' }

Write-Host 'Files staged for the commit:'
foreach ($path in $stagedPaths) { Write-Host "  $path" }

$defaultMessage = "Update Preloved Little Pages website ($(Get-Date -Format 'yyyy-MM-dd'))"
$commitMessage = Read-Host "Commit message (press Enter for '$defaultMessage')"
if ([string]::IsNullOrWhiteSpace($commitMessage)) { $commitMessage = $defaultMessage }

& git commit -m $commitMessage
if ($LASTEXITCODE -ne 0) { throw 'Commit failed. No push was attempted.' }

& git push -u origin main
if ($LASTEXITCODE -ne 0) { throw 'Push failed. No force push was attempted.' }

Write-Host 'Website changes were pushed to origin/main.'
