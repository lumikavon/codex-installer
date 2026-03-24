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

function Install-NodeJs {
    Write-Step "1/5 Install Node.js"

    $nodeOk = $false
    if ((Command-Exists "node") -and (Command-Exists "npm")) {
        $major = Get-NodeMajor
        if ($major -ge 18) {
            $nodeOk = $true
            Write-Info "Node.js already available: $(node --version)"
        } else {
            Write-Warn "Node.js version too old: $(node --version). Need >= 18."
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
    Write-Ok "Node.js ready: $(node --version) / npm $(npm --version)"
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

    Refresh-Path
    if (Command-Exists "codex") {
        Write-Ok "Codex installed: $(codex --version)"
    } else {
        Write-Warn "codex command not visible yet in current shell. Reopen terminal and retry."
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

    if ([string]::IsNullOrWhiteSpace($OpenAIBaseUrl)) {
        $enteredBase = Read-Host "OPENAI_BASE_URL (Enter for default: $DefaultOpenAIBaseUrl)"
        if ([string]::IsNullOrWhiteSpace($enteredBase)) {
            $OpenAIBaseUrl = $DefaultOpenAIBaseUrl
        } else {
            $OpenAIBaseUrl = $enteredBase.Trim()
        }
    }

    if ([string]::IsNullOrWhiteSpace($OpenAIApiKey)) {
        $secure = Read-Host "OPENAI_API_KEY" -AsSecureString
        $OpenAIApiKey = Convert-SecureStringToPlainText -Secure $secure
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
    if ([string]::IsNullOrEmpty($Value)) {
        return ""
    }
    if ($Value.Length -le 8) {
        return "********"
    }
    return "{0}****{1}" -f $Value.Substring(0, 4), $Value.Substring($Value.Length - 4)
}

function Print-Summary {
    Write-Step "5/5 Print install summary"

    $nodeVersion = if (Command-Exists "node") { (node --version).Trim() } else { "not found" }
    $npmVersion = if (Command-Exists "npm") { (npm --version).Trim() } else { "not found" }
    $codexVersion = if (Command-Exists "codex") { (codex --version).Trim() } else { "not found" }

    Write-Host ""
    Write-Host "Install Result"
    Write-Host "  node             : $nodeVersion"
    Write-Host "  npm              : $npmVersion"
    Write-Host "  codex            : $codexVersion"
    Write-Host "  OPENAI_BASE_URL  : $OpenAIBaseUrl"
    Write-Host "  OPENAI_API_KEY   : $(Mask-Secret $OpenAIApiKey)"
    Write-Host "  auth.json        : $AuthFile"
    Write-Host "  config.toml      : $ConfigFile"
    Write-Host "  env script       : $EnvFile"
    Write-Host ""
    Write-Host "GitHub one-line install (replace owner/repo/ref):"
    Write-Host "  irm https://raw.githubusercontent.com/<owner>/<repo>/<ref>/.agents/skills/agents-installer/scripts/install-codex.ps1 | iex"
}

Install-NodeJs
Install-Codex
Read-OpenAIInput
Write-CodexConfig -ApiKey $OpenAIApiKey -BaseUrl $OpenAIBaseUrl
Print-Summary
