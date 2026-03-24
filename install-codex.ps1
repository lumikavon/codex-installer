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
$DesiredNpmCache = "D:\npm-cache"
$DesiredNpmPrefix = "D:\npm-global"
$script:PreferredProcessPathEntries = @()

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

function Test-IsWindows {
    return $env:OS -eq "Windows_NT"
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

    foreach ($entry in @($script:PreferredProcessPathEntries)) {
        if (-not [string]::IsNullOrWhiteSpace($entry) -and (Test-Path $entry)) {
            Add-ProcessPathEntryFirst -Entry $entry | Out-Null
        }
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

function Add-ProcessPathEntryFirst([string]$Entry) {
    $normalizedEntry = Normalize-PathEntry -PathEntry $Entry
    if ([string]::IsNullOrWhiteSpace($normalizedEntry)) {
        return $false
    }

    $existingEntries = @(
        Split-PathEntries -PathValue $env:Path | Where-Object {
            -not [string]::Equals(
                (Normalize-PathEntry -PathEntry $_),
                $normalizedEntry,
                [System.StringComparison]::OrdinalIgnoreCase
            )
        }
    )

    $env:Path = (@($normalizedEntry) + $existingEntries) -join ";"
    return $true
}

function Register-PreferredProcessPathEntry([string]$Entry) {
    $normalizedEntry = Normalize-PathEntry -PathEntry $Entry
    if ([string]::IsNullOrWhiteSpace($normalizedEntry)) {
        return $false
    }

    foreach ($existingEntry in @($script:PreferredProcessPathEntries)) {
        if ([string]::Equals(
                (Normalize-PathEntry -PathEntry $existingEntry),
                $normalizedEntry,
                [System.StringComparison]::OrdinalIgnoreCase
            )) {
            return $false
        }
    }

    $script:PreferredProcessPathEntries += $normalizedEntry
    return $true
}

function Test-PathUnderRoot {
    param(
        [string]$PathValue,
        [string]$RootPath
    )

    $normalizedPath = Normalize-PathEntry -PathEntry $PathValue
    $normalizedRoot = Normalize-PathEntry -PathEntry $RootPath
    if ([string]::IsNullOrWhiteSpace($normalizedPath) -or [string]::IsNullOrWhiteSpace($normalizedRoot)) {
        return $false
    }

    if ([string]::Equals($normalizedPath, $normalizedRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $true
    }

    $rootWithSeparator = $normalizedRoot.TrimEnd('\') + '\'
    return $normalizedPath.StartsWith($rootWithSeparator, [System.StringComparison]::OrdinalIgnoreCase)
}

function Get-ScoopRoot {
    if (-not [string]::IsNullOrWhiteSpace($env:SCOOP)) {
        return (Normalize-PathEntry -PathEntry $env:SCOOP)
    }

    return (Normalize-PathEntry -PathEntry (Join-Path $HOME "scoop"))
}

function Get-ScoopShimsPath {
    return Join-Path (Get-ScoopRoot) "shims"
}

function Get-ScoopCommandPath {
    foreach ($candidate in @(
            (Join-Path (Get-ScoopShimsPath) "scoop.cmd"),
            (Join-Path (Get-ScoopShimsPath) "scoop.ps1")
        )) {
        if (Test-Path $candidate) {
            return $candidate
        }
    }

    return Get-CommandPath -CommandName "scoop" -PreferredLeafNames @("scoop.cmd", "scoop.ps1")
}

function Ensure-ScoopOnPath {
    $scoopShims = Get-ScoopShimsPath
    if (-not (Test-Path $scoopShims)) {
        return ""
    }

    Register-PreferredProcessPathEntry -Entry $scoopShims | Out-Null
    if (Add-UserPathEntry -Entry $scoopShims) {
        Write-Info "Added Scoop shims to user PATH: $scoopShims"
    }

    Refresh-Path
    return $scoopShims
}

function Test-ExecutionPolicyAllowsScriptInstall([string]$Policy) {
    return $Policy -in @("Bypass", "Unrestricted", "RemoteSigned")
}

function Ensure-ScoopInstallExecutionPolicy {
    $effectivePolicy = Get-ExecutionPolicy
    if (Test-ExecutionPolicyAllowsScriptInstall -Policy $effectivePolicy) {
        Write-Info "PowerShell execution policy already allows Scoop install: $effectivePolicy"
        return
    }

    try {
        Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force -ErrorAction Stop
    } catch {
        $effectivePolicy = Get-ExecutionPolicy
        if (Test-ExecutionPolicyAllowsScriptInstall -Policy $effectivePolicy) {
            Write-Info "PowerShell execution policy is already usable because a more specific scope applies: $effectivePolicy"
            return
        }

        try {
            Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force -ErrorAction Stop
        } catch {
            $effectivePolicy = Get-ExecutionPolicy
            if (Test-ExecutionPolicyAllowsScriptInstall -Policy $effectivePolicy) {
                Write-Info "PowerShell execution policy is usable after fallback: $effectivePolicy"
                return
            }

            throw "Unable to enable a PowerShell execution policy for Scoop install. Current effective policy: $effectivePolicy"
        }
    }

    $effectivePolicy = Get-ExecutionPolicy
    if (-not (Test-ExecutionPolicyAllowsScriptInstall -Policy $effectivePolicy)) {
        throw "PowerShell execution policy still blocks Scoop install: $effectivePolicy"
    }

    Write-Info "PowerShell execution policy ready for Scoop install: $effectivePolicy"
}

function Ensure-Scoop {
    if (Command-Exists "scoop") {
        Ensure-ScoopOnPath | Out-Null
        return [string](Get-ScoopCommandPath)
    }

    Write-Info "Scoop not found. Installing Scoop..."
    Ensure-ScoopInstallExecutionPolicy
    Invoke-Expression (Invoke-RestMethod -Uri "https://get.scoop.sh") | Out-Null

    Ensure-ScoopOnPath | Out-Null
    $scoopCommand = [string](Get-ScoopCommandPath)
    if ([string]::IsNullOrWhiteSpace($scoopCommand) -or (-not (Test-Path $scoopCommand))) {
        throw "Scoop installation failed. Could not find scoop command after installation."
    }

    Write-Ok "Scoop ready: $(Get-CommandOutputText -CommandPath $scoopCommand -Arguments @('--version'))"
    return $scoopCommand
}

function Get-NodeCommandPath {
    return Get-CommandPath -CommandName "node" -PreferredLeafNames @("node.exe", "node.cmd", "node")
}

function Get-NpmCommandPath {
    return Get-CommandPath -CommandName "npm" -PreferredLeafNames @("npm.cmd", "npm.exe", "npm")
}

function Test-NodeReadyFromScoop {
    return (Test-NodeReady) -and
        (Test-PathUnderRoot -PathValue (Get-NodeCommandPath) -RootPath (Get-ScoopRoot)) -and
        (Test-PathUnderRoot -PathValue (Get-NpmCommandPath) -RootPath (Get-ScoopRoot))
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
        [string]$CommandName = "",
        [string]$CommandPath = "",
        [string[]]$Arguments = @(),
        [string]$Fallback = "not found"
    )

    $target = ""
    if (-not [string]::IsNullOrWhiteSpace($CommandPath)) {
        if (-not (Test-Path $CommandPath)) {
            return $Fallback
        }
        $target = $CommandPath
    } elseif (-not [string]::IsNullOrWhiteSpace($CommandName)) {
        if (-not (Command-Exists $CommandName)) {
            return $Fallback
        }
        $target = $CommandName
    } else {
        return $Fallback
    }

    try {
        $output = & $target @Arguments 2>$null
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

function Get-CodexShimCandidates {
    if (Test-IsWindows) {
        return @("codex.ps1", "codex.cmd", "codex")
    }

    return @("codex")
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

function Get-NpmConfigValue([string]$Key) {
    if (-not (Command-Exists "npm")) {
        return ""
    }

    try {
        $output = & npm config get $Key 2>$null
        if ($LASTEXITCODE -ne 0 -or $null -eq $output) {
            return ""
        }

        $text = ((@($output) | ForEach-Object { "$_" }) -join [Environment]::NewLine).Trim()
        if ([string]::IsNullOrWhiteSpace($text) -or $text -eq "undefined" -or $text -eq "null") {
            return ""
        }

        return $text
    } catch {
        return ""
    }
}

function Set-NpmGlobalConfigValue {
    param(
        [string]$Key,
        [string]$Value
    )

    & npm config set $Key $Value --global | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to set npm $Key to $Value."
    }
}

function Ensure-NpmGlobalPrefixOnPath {
    $prefix = Get-NpmGlobalPrefix
    if ([string]::IsNullOrWhiteSpace($prefix)) {
        return ""
    }

    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    if (-not (Test-PathContainsEntry -PathValue $userPath -Entry $prefix)) {
        if (Add-UserPathEntry -Entry $prefix) {
            Write-Info "Added npm global prefix to user PATH: $prefix"
        }
    }

    Refresh-Path
    return $prefix
}

function Ensure-NpmDefaults {
    if (-not (Command-Exists "npm")) {
        throw "npm not found. Node.js install failed."
    }

    foreach ($path in @($DesiredNpmCache, $DesiredNpmPrefix)) {
        if (-not (Test-Path $path)) {
            New-Item -ItemType Directory -Path $path -Force | Out-Null
        }
    }

    $currentCache = Get-NpmConfigValue -Key "cache"
    if (-not (Paths-Match -Left $currentCache -Right $DesiredNpmCache)) {
        Set-NpmGlobalConfigValue -Key "cache" -Value $DesiredNpmCache
        Write-Info "Set npm cache: $DesiredNpmCache"
    }

    $currentPrefix = Get-NpmGlobalPrefix
    if (-not (Paths-Match -Left $currentPrefix -Right $DesiredNpmPrefix)) {
        Set-NpmGlobalConfigValue -Key "prefix" -Value $DesiredNpmPrefix
        Write-Info "Set npm global prefix: $DesiredNpmPrefix"
    }

    $effectiveCache = Get-NpmConfigValue -Key "cache"
    if (-not (Paths-Match -Left $effectiveCache -Right $DesiredNpmCache)) {
        throw "npm cache is $effectiveCache, expected $DesiredNpmCache."
    }

    $effectivePrefix = Get-NpmGlobalPrefix
    if (-not (Paths-Match -Left $effectivePrefix -Right $DesiredNpmPrefix)) {
        throw "npm global prefix is $effectivePrefix, expected $DesiredNpmPrefix."
    }

    Ensure-NpmGlobalPrefixOnPath | Out-Null
}

function Get-CodexShimPath {
    param(
        [string]$Prefix = ""
    )

    $prefix = $Prefix
    if ([string]::IsNullOrWhiteSpace($prefix)) {
        $prefix = Get-NpmGlobalPrefix
    }

    if ([string]::IsNullOrWhiteSpace($prefix)) {
        return ""
    }

    foreach ($candidate in (Get-CodexShimCandidates)) {
        $candidatePath = Join-Path $prefix $candidate
        if (Test-Path $candidatePath) {
            return $candidatePath
        }
    }

    return ""
}

function Ensure-PowerShellCodexShim {
    param(
        [string]$Prefix
    )

    if (-not (Test-IsWindows) -or [string]::IsNullOrWhiteSpace($Prefix)) {
        return ""
    }

    $ps1Path = Join-Path $Prefix "codex.ps1"
    if (Test-Path $ps1Path) {
        return $ps1Path
    }

    $cmdPath = Join-Path $Prefix "codex.cmd"
    if (-not (Test-Path $cmdPath)) {
        return ""
    }

    $payload = @'
$cmdShim = Join-Path $PSScriptRoot "codex.cmd"
& $cmdShim @args
exit $LASTEXITCODE
'@

    Upsert-ManagedBlock -Path $ps1Path -Payload $payload.TrimEnd()
    Write-Info "Created PowerShell codex launcher: $ps1Path"
    return $ps1Path
}

function Get-CommandPath {
    param(
        [string]$CommandName,
        [string[]]$PreferredLeafNames = @()
    )

    $commands = @(Get-Command $CommandName -All -ErrorAction SilentlyContinue | Where-Object {
            -not [string]::IsNullOrWhiteSpace($_.Path)
        })
    if ($commands.Count -eq 0) {
        return ""
    }

    $firstCommand = $commands[0]
    $firstCommandDirectory = Normalize-PathEntry -PathEntry (Split-Path -Parent $firstCommand.Path)
    $sameDirectoryCommands = @($commands | Where-Object {
            [string]::Equals(
                (Normalize-PathEntry -PathEntry (Split-Path -Parent $_.Path)),
                $firstCommandDirectory,
                [System.StringComparison]::OrdinalIgnoreCase
            )
        })

    foreach ($preferredLeafName in $PreferredLeafNames) {
        $match = $sameDirectoryCommands | Where-Object {
            (-not [string]::IsNullOrWhiteSpace($_.Path)) -and
            [string]::Equals(
                [System.IO.Path]::GetFileName($_.Path),
                $preferredLeafName,
                [System.StringComparison]::OrdinalIgnoreCase
            )
        } | Select-Object -First 1

        if ($null -ne $match) {
            return $match.Path
        }
    }

    return $firstCommand.Path
}

function Get-CodexVisiblePath {
    return Get-CommandPath -CommandName "codex" -PreferredLeafNames (Get-CodexShimCandidates)
}

function Get-CodexStatus {
    param(
        [string]$InstalledCodexPath = "",
        [string]$VisibleCodexPath = ""
    )

    $installedPath = $InstalledCodexPath
    if ([string]::IsNullOrWhiteSpace($installedPath)) {
        $installedPath = Get-CodexShimPath
    }

    $visiblePath = $VisibleCodexPath
    if ([string]::IsNullOrWhiteSpace($visiblePath)) {
        $visiblePath = Get-CodexVisiblePath
    }

    $installedVersion = if (-not [string]::IsNullOrWhiteSpace($installedPath)) {
        Get-CommandOutputText -CommandPath $installedPath -Arguments @("--version")
    } else {
        "not found"
    }

    $visibleVersion = if (-not [string]::IsNullOrWhiteSpace($visiblePath)) {
        Get-CommandOutputText -CommandPath $visiblePath -Arguments @("--version")
    } else {
        "not found"
    }

    $installedOnPath = (-not [string]::IsNullOrWhiteSpace($installedPath)) -and
        (-not [string]::IsNullOrWhiteSpace($visiblePath)) -and
        (Paths-Match -Left $installedPath -Right $visiblePath)
    $hasConflict = (-not [string]::IsNullOrWhiteSpace($installedPath)) -and
        (-not [string]::IsNullOrWhiteSpace($visiblePath)) -and
        (-not (Paths-Match -Left $installedPath -Right $visiblePath))

    $displayVersion = "not found"
    $displayPath = if (-not [string]::IsNullOrWhiteSpace($visiblePath)) {
        $visiblePath
    } elseif (-not [string]::IsNullOrWhiteSpace($installedPath)) {
        $installedPath
    } else {
        "not found"
    }

    if ($hasConflict -and ($installedVersion -ne "not found")) {
        $displayVersion = "installed, but current PATH resolves to another codex command"
    } elseif ($installedOnPath -and ($visibleVersion -ne "not found")) {
        $displayVersion = $visibleVersion
    } elseif (($installedVersion -ne "not found") -and (-not $installedOnPath)) {
        $displayVersion = "installed but not on PATH in current shell"
        $displayPath = $installedPath
    } elseif ($visibleVersion -ne "not found") {
        $displayVersion = $visibleVersion
    }

    return [PSCustomObject]@{
        InstalledPath    = $installedPath
        VisiblePath      = $visiblePath
        InstalledVersion = $installedVersion
        VisibleVersion   = $visibleVersion
        InstalledOnPath  = $installedOnPath
        HasConflict      = $hasConflict
        DisplayVersion   = $displayVersion
        DisplayPath      = $displayPath
    }
}

function Install-NodeJs {
    Write-Step "1/5 Install Node.js"

    $scoopCommand = @(
        Ensure-Scoop | Where-Object { -not [string]::IsNullOrWhiteSpace("$_") }
    ) | Select-Object -Last 1
    $scoopCommand = [string]$scoopCommand
    $nodeOk = $false

    if (Test-NodeReadyFromScoop) {
        $nodeOk = $true
        Write-Info "Scoop Node.js already available: $(Get-CommandOutputText -CommandName 'node' -Arguments @('--version'))"
    } elseif ((Command-Exists "node") -and (Command-Exists "npm")) {
        $currentNodeVersion = Get-CommandOutputText -CommandName "node" -Arguments @("--version") -Fallback "unknown"
        if ((Get-NodeMajor) -ge 18) {
            Write-Warn "Existing Node.js/npm are not provided by Scoop. Installing scoop nodejs-lts and prioritizing Scoop shims."
            Write-Info "Current node path: $(Get-NodeCommandPath)"
            Write-Info "Current npm path: $(Get-NpmCommandPath)"
        } else {
            Write-Warn "Node.js version too old: $currentNodeVersion. Need Scoop nodejs-lts >= 18."
        }
    }

    if (-not $nodeOk) {
        Write-Info "Installing Node.js with Scoop"
        & $scoopCommand install nodejs-lts
        $installExitCode = $LASTEXITCODE
        Ensure-ScoopOnPath | Out-Null

        if ($installExitCode -ne 0) {
            throw "Scoop nodejs-lts installation failed (exit code $installExitCode)."
        }

        if (Test-NodeReadyFromScoop) {
            $nodeOk = $true
        } else {
            throw "Node.js/npm are still not being resolved from Scoop after installation."
        }
    }

    Ensure-ScoopOnPath | Out-Null

    if (-not (Test-NodeReadyFromScoop)) {
        throw "Node.js/npm not found from Scoop after installation."
    }

    if ((Get-NodeMajor) -lt 18) {
        throw "Installed Scoop Node.js is still < 18. Please upgrade Node.js."
    }

    & npm config set registry $NpmRegistry --global | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to set npm registry to $NpmRegistry."
    }

    Ensure-NpmDefaults
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
    Ensure-PowerShellCodexShim -Prefix $npmPrefix | Out-Null
    $installedCodexPath = Get-CodexShimPath -Prefix $npmPrefix
    $visibleCodexPath = Get-CodexVisiblePath
    $codexStatus = Get-CodexStatus -InstalledCodexPath $installedCodexPath -VisibleCodexPath $visibleCodexPath

    if ($codexStatus.InstalledVersion -ne "not found") {
        if ($codexStatus.HasConflict) {
            Write-Warn "Codex installed: $($codexStatus.InstalledVersion)"
            Write-Warn "Codex was installed to $installedCodexPath, but the current shell resolves 'codex' to $visibleCodexPath. Reopen terminal or fix PATH ordering."
        } elseif ($codexStatus.InstalledOnPath) {
            Write-Ok "Codex installed: $($codexStatus.InstalledVersion)"
        } else {
            Write-Warn "Codex installed: $($codexStatus.InstalledVersion)"
            Write-Warn "Codex was installed under $npmPrefix but is not visible yet in the current shell. Reopen terminal and retry."
        }
    } elseif (-not [string]::IsNullOrWhiteSpace($installedCodexPath)) {
        Write-Warn "Codex launcher was found at $installedCodexPath, but '--version' did not return successfully."
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
    $codexStatus = Get-CodexStatus
    $codexVersion = $codexStatus.DisplayVersion
    $codexPath = $codexStatus.DisplayPath

    if ([string]::IsNullOrWhiteSpace($codexPath)) {
        $codexPath = "not found"
    }

    $npmPrefix = Get-NpmGlobalPrefix
    if ([string]::IsNullOrWhiteSpace($npmPrefix)) {
        $npmPrefix = "unknown"
    }

    $npmCache = Get-NpmConfigValue -Key "cache"
    if ([string]::IsNullOrWhiteSpace($npmCache)) {
        $npmCache = "unknown"
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
    Write-Host "  npm cache        : $npmCache"
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
