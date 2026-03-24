[CmdletBinding()]
param(
    [string]$OpenAIApiKey = "",
    [string]$OpenAIBaseUrl = "",
    [string]$NpmRegistry = "https://registry.npmjs.org"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$DefaultOpenAIBaseUrl = "https://api.openai.com/v1"
$CodexDir = Join-Path $HOME ".codex"
$AuthFile = Join-Path $CodexDir "auth.json"
$ConfigFile = Join-Path $CodexDir "config.toml"
$EnvFile = Join-Path $CodexDir "env.ps1"

function Write-Step([string]$Message) {
    Write-Host "[STEP] $Message" -ForegroundColor Cyan
}

function Write-Info([string]$Message) {
    Write-Host "[INFO] $Message" -ForegroundColor Gray
}

function Write-Warn([string]$Message) {
    Write-Host "[WARN] $Message" -ForegroundColor Yellow
}

function Write-Ok([string]$Message) {
    Write-Host "[ OK ] $Message" -ForegroundColor Green
}

function Command-Exists([string]$CommandName) {
    return $null -ne (Get-Command $CommandName -ErrorAction SilentlyContinue)
}

function Refresh-Path {
    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
    $parts = @()
    if (-not [string]::IsNullOrWhiteSpace($machinePath)) { $parts += $machinePath }
    if (-not [string]::IsNullOrWhiteSpace($userPath)) { $parts += $userPath }
    if ($parts.Count -gt 0) {
        $env:Path = ($parts -join ";")
    }
}

function Normalize-PathEntry([string]$PathEntry) {
    if ([string]::IsNullOrWhiteSpace($PathEntry)) {
        return ""
    }

    return $PathEntry.Trim().Trim('"').TrimEnd('\')
}

function Split-PathEntries([string]$PathValue) {
    if ([string]::IsNullOrWhiteSpace($PathValue)) {
        return @()
    }

    return @($PathValue -split ";" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
}

function Test-PathContainsEntry {
    param(
        [string]$PathValue,
        [string]$Entry
    )

    $normalizedEntry = Normalize-PathEntry -PathEntry $Entry
    if ([string]::IsNullOrWhiteSpace($normalizedEntry)) {
        return $false
    }

    foreach ($existingEntry in (Split-PathEntries -PathValue $PathValue)) {
        if ([string]::Equals(
                (Normalize-PathEntry -PathEntry $existingEntry),
                $normalizedEntry,
                [System.StringComparison]::OrdinalIgnoreCase
            )) {
            return $true
        }
    }

    return $false
}

function Paths-Match {
    param(
        [string]$Left,
        [string]$Right
    )

    $normalizedLeft = Normalize-PathEntry -PathEntry $Left
    $normalizedRight = Normalize-PathEntry -PathEntry $Right

    if ([string]::IsNullOrWhiteSpace($normalizedLeft) -or [string]::IsNullOrWhiteSpace($normalizedRight)) {
        return $false
    }

    return [string]::Equals($normalizedLeft, $normalizedRight, [System.StringComparison]::OrdinalIgnoreCase)
}

function Add-UserPathEntry([string]$Entry) {
    $normalizedEntry = Normalize-PathEntry -PathEntry $Entry
    if ([string]::IsNullOrWhiteSpace($normalizedEntry)) {
        return $false
    }

    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    if (Test-PathContainsEntry -PathValue $userPath -Entry $normalizedEntry) {
        return $false
    }

    $updatedEntries = Split-PathEntries -PathValue $userPath
    $updatedEntries += $normalizedEntry
    [Environment]::SetEnvironmentVariable("Path", ($updatedEntries -join ";"), "User")
    return $true
}

function Get-NodeMajor {
    if (-not (Command-Exists "node")) {
        return 0
    }
    $version = (node --version).Trim()
    if ($version -match "^v(\d+)") {
        return [int]$Matches[1]
    }
    return 0
}

function Test-NodeReady {
    return (Command-Exists "node") -and (Command-Exists "npm") -and ((Get-NodeMajor) -ge 18)
}

function Get-CommandOutputText {
    param(
        [string]$CommandName,
        [string[]]$Arguments = @(),
        [string]$Fallback = "not found"
    )

    if (-not (Command-Exists $CommandName)) {
        return $Fallback
    }

    try {
        $output = & $CommandName @Arguments 2>$null
        if ($LASTEXITCODE -ne 0 -or $null -eq $output) {
            return $Fallback
        }

        $text = (@($output) | ForEach-Object { "$_" }) -join [Environment]::NewLine
        if ([string]::IsNullOrWhiteSpace($text)) {
            return $Fallback
        }

        return ($text + "").Trim()
    } catch {
        return $Fallback
    }
}

function Get-NpmGlobalPrefix {
    if (-not (Command-Exists "npm")) {
        return ""
    }

    try {
        $output = & npm prefix -g 2>$null
        if ($LASTEXITCODE -ne 0 -or $null -eq $output) {
            return ""
        }

        $text = (@($output) | ForEach-Object { "$_" }) -join [Environment]::NewLine
        if ([string]::IsNullOrWhiteSpace($text)) {
            return ""
        }

        return ($text + "").Trim()
    } catch {
        return ""
    }
}

function Ensure-NpmGlobalPrefixOnPath {
    $prefix = Get-NpmGlobalPrefix
    if ([string]::IsNullOrWhiteSpace($prefix)) {
        return ""
    }

    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")

    if ((-not (Test-PathContainsEntry -PathValue $userPath -Entry $prefix)) -and
        (-not (Test-PathContainsEntry -PathValue $machinePath -Entry $prefix))) {
        if (Add-UserPathEntry -Entry $prefix) {
            Write-Info "Added npm global prefix to user PATH: $prefix"
        }
    }

    Refresh-Path
    return $prefix
}

function Get-CodexShimPath {
    $prefix = Get-NpmGlobalPrefix
    if ([string]::IsNullOrWhiteSpace($prefix)) {
        return ""
    }

    foreach ($candidate in @("codex.cmd", "codex.ps1", "codex")) {
        $candidatePath = Join-Path $prefix $candidate
        if (Test-Path $candidatePath) {
            return $candidatePath
        }
    }

    return ""
}

function Get-CommandPath([string]$CommandName) {
    $command = Get-Command $CommandName -ErrorAction SilentlyContinue
    if ($null -eq $command) {
        return ""
    }

    return $command.Path
}

function Install-NodeJs {
    Write-Step "1/5 Install Node.js"

    $nodeOk = $false
    if ((Command-Exists "node") -and (Command-Exists "npm")) {
        $major = Get-NodeMajor
        if ($major -ge 18) {
            $nodeOk = $true
            Write-Info "Node.js already available: $(Get-CommandOutputText -CommandName 'node' -Arguments @('--version'))"
        } else {
            Write-Warn "Node.js version too old: $(Get-CommandOutputText -CommandName 'node' -Arguments @('--version') -Fallback 'unknown'). Need >= 18."
        }
    }

    if (-not $nodeOk) {
        $attemptedManagers = @()

        if (Command-Exists "winget") {
            $attemptedManagers += "winget"
            Write-Info "Installing Node.js with winget (source: winget)"
            & winget install --id OpenJS.NodeJS.LTS -e --source winget --accept-source-agreements --accept-package-agreements --silent
            Refresh-Path
            if (Test-NodeReady) {
                $nodeOk = $true
            }
            if ($LASTEXITCODE -ne 0) {
                Write-Warn "winget returned non-zero exit code ($LASTEXITCODE). Trying other package managers if available."
            }
        }

        if ((-not $nodeOk) -and (Command-Exists "scoop")) {
            $attemptedManagers += "scoop"
            Write-Info "Installing Node.js with scoop"
            & scoop install nodejs-lts
            Refresh-Path
            if (Test-NodeReady) {
                $nodeOk = $true
            } elseif ($LASTEXITCODE -ne 0) {
                Write-Warn "scoop installation failed (exit code $LASTEXITCODE)."
            }
        }

        if ((-not $nodeOk) -and (Command-Exists "choco")) {
            $attemptedManagers += "choco"
            Write-Info "Installing Node.js with chocolatey"
            & choco install -y nodejs-lts
            Refresh-Path
            if (Test-NodeReady) {
                $nodeOk = $true
            } elseif ($LASTEXITCODE -ne 0) {
                Write-Warn "chocolatey installation failed (exit code $LASTEXITCODE)."
            }
        }

        if ($attemptedManagers.Count -eq 0) {
            throw "No supported package manager found (winget/scoop/choco). Install Node.js 18+ manually."
        }
    }

    Refresh-Path

    if ((-not (Command-Exists "node")) -or (-not (Command-Exists "npm"))) {
        throw "Node.js/npm not found after installation."
    }

    if ((Get-NodeMajor) -lt 18) {
        throw "Installed Node.js is still < 18. Please upgrade Node.js."
    }

    & npm config set registry $NpmRegistry --global | Out-Null
    Write-Ok "Node.js ready: $(Get-CommandOutputText -CommandName 'node' -Arguments @('--version')) / npm $(Get-CommandOutputText -CommandName 'npm' -Arguments @('--version'))"
}

function Install-Codex {
    Write-Step "2/5 Install Codex"
    if (-not (Command-Exists "npm")) {
        throw "npm not found. Node.js install failed."
    }

    & npm install -g @openai/codex "--registry=$NpmRegistry"
    if ($LASTEXITCODE -ne 0) {
        throw "Codex installation failed."
    }

    $npmPrefix = Ensure-NpmGlobalPrefixOnPath
    $codexVersion = Get-CommandOutputText -CommandName "codex" -Arguments @("--version")
    $visibleCodexPath = Get-CommandPath -CommandName "codex"
    $installedCodexPath = Get-CodexShimPath

    if ($codexVersion -ne "not found") {
        Write-Ok "Codex installed: $codexVersion"
    } elseif (-not [string]::IsNullOrWhiteSpace($installedCodexPath)) {
        if ((-not [string]::IsNullOrWhiteSpace($visibleCodexPath)) -and
            (-not (Paths-Match -Left $visibleCodexPath -Right $installedCodexPath))) {
            Write-Warn "Codex was installed to $installedCodexPath, but the current shell resolves 'codex' to $visibleCodexPath. Reopen terminal or fix PATH ordering."
        } else {
            Write-Warn "Codex was installed under $npmPrefix but is not visible yet in the current shell. Reopen terminal and retry."
        }
    } else {
        Write-Warn "npm install completed, but no codex launcher was found under $npmPrefix."
    }
}

function Convert-SecureStringToPlainText([Security.SecureString]$Secure) {
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Secure)
    try {
        return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    } finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    }
}

function Read-OpenAIInput {
    Write-Step "3/5 Prompt OPENAI_BASE_URL and OPENAI_API_KEY"

    if ([string]::IsNullOrWhiteSpace($script:OpenAIBaseUrl)) {
        $enteredBase = Read-Host "OPENAI_BASE_URL (Enter for default: $DefaultOpenAIBaseUrl)"
        if ([string]::IsNullOrWhiteSpace($enteredBase)) {
            $script:OpenAIBaseUrl = $DefaultOpenAIBaseUrl
        } else {
            $script:OpenAIBaseUrl = $enteredBase.Trim()
        }
    }

    if ([string]::IsNullOrWhiteSpace($script:OpenAIApiKey)) {
        $secure = Read-Host "OPENAI_API_KEY" -AsSecureString
        $script:OpenAIApiKey = Convert-SecureStringToPlainText -Secure $secure
    }

    if ([string]::IsNullOrWhiteSpace($OpenAIApiKey)) {
        throw "OPENAI_API_KEY cannot be empty."
    }
}

function Escape-SingleQuotedString([string]$Value) {
    return $Value -replace "'", "''"
}

function Upsert-ManagedBlock {
    param(
        [string]$Path,
        [string]$Payload
    )

    if (-not (Test-Path (Split-Path -Parent $Path))) {
        New-Item -ItemType Directory -Path (Split-Path -Parent $Path) -Force | Out-Null
    }

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Payload, $utf8NoBom)
}

function Write-CodexConfig {
    param(
        [string]$ApiKey,
        [string]$BaseUrl
    )

    Write-Step "4/5 Configure Codex"

    New-Item -ItemType Directory -Path $CodexDir -Force | Out-Null

    $authJson = @{ OPENAI_API_KEY = $ApiKey } | ConvertTo-Json
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($AuthFile, $authJson, $utf8NoBom)

    $payload = @"
model_provider = "aicodemirror"
model = "gpt-5.4"
model_reasoning_effort = "xhigh"
disable_response_storage = true
preferred_auth_method = "apikey"
personality = "pragmatic"

[model_providers.aicodemirror]
name = "aicodemirror"
base_url = "$BaseUrl"
wire_api = "responses"
"@
    Upsert-ManagedBlock -Path $ConfigFile -Payload $payload.TrimEnd()

    # New codex version no longer requires OPENAI environment variables in script
    if (Test-Path $EnvFile) { Remove-Item $EnvFile -Force -ErrorAction SilentlyContinue }

    Write-Ok "Codex config written to $CodexDir"
}

function Mask-Secret([string]$Value) {
    if ($null -eq $Value -or $Value.Length -eq 0) {
        return ""
    }
    if ($Value.Length -le 8) {
        return "********"
    }
    return "{0}****{1}" -f $Value.Substring(0, 4), $Value.Substring($Value.Length - 4)
}

function Print-Summary {
    Write-Step "5/5 Print install summary"

    $nodeVersion = Get-CommandOutputText -CommandName "node" -Arguments @("--version")
    $npmVersion = Get-CommandOutputText -CommandName "npm" -Arguments @("--version")
    $codexVersion = Get-CommandOutputText -CommandName "codex" -Arguments @("--version")
    $visibleCodexPath = Get-CommandPath -CommandName "codex"
    $installedCodexPath = Get-CodexShimPath
    $codexPath = if (($codexVersion -ne "not found") -and (-not [string]::IsNullOrWhiteSpace($visibleCodexPath))) {
        $visibleCodexPath
    } elseif (-not [string]::IsNullOrWhiteSpace($installedCodexPath)) {
        $installedCodexPath
    } else {
        $visibleCodexPath
    }

    if ([string]::IsNullOrWhiteSpace($codexPath)) {
        $codexPath = "not found"
    }

    if (($codexVersion -eq "not found") -and (-not [string]::IsNullOrWhiteSpace($installedCodexPath))) {
        if ((-not [string]::IsNullOrWhiteSpace($visibleCodexPath)) -and
            (-not (Paths-Match -Left $visibleCodexPath -Right $installedCodexPath))) {
            $codexVersion = "installed, but current PATH resolves to another codex command"
        } else {
            $codexVersion = "installed but not on PATH in current shell"
        }
    }

    $npmPrefix = Get-NpmGlobalPrefix
    if ([string]::IsNullOrWhiteSpace($npmPrefix)) {
        $npmPrefix = "unknown"
    }

    $prefixOnPath = if ($npmPrefix -eq "unknown") {
        "unknown"
    } elseif (Test-PathContainsEntry -PathValue $env:Path -Entry $npmPrefix) {
        "yes"
    } else {
        "no"
    }

    $envScriptStatus = if (Test-Path $EnvFile) {
        $EnvFile
    } else {
        "not used (Codex reads auth.json/config.toml)"
    }

    Write-Host ""
    Write-Host "Install Result"
    Write-Host "  node             : $nodeVersion"
    Write-Host "  npm              : $npmVersion"
    Write-Host "  codex            : $codexVersion"
    Write-Host "  codex path       : $codexPath"
    Write-Host "  npm prefix       : $npmPrefix"
    Write-Host "  prefix on PATH   : $prefixOnPath"
    Write-Host "  OPENAI_BASE_URL  : $script:OpenAIBaseUrl"
    Write-Host "  OPENAI_API_KEY   : $(Mask-Secret $script:OpenAIApiKey)"
    Write-Host "  auth.json        : $AuthFile"
    Write-Host "  config.toml      : $ConfigFile"
    Write-Host "  env script       : $envScriptStatus"
    Write-Host ""
    Write-Host "GitHub one-line install (replace owner/repo/ref):"
    Write-Host "  irm https://raw.githubusercontent.com/<owner>/<repo>/<ref>/install-codex.ps1 | iex"
}

Install-NodeJs
Install-Codex
Read-OpenAIInput
Write-CodexConfig -ApiKey $OpenAIApiKey -BaseUrl $OpenAIBaseUrl
Print-Summary
