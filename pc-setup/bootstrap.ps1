# pc-setup/bootstrap.ps1 - Windows PowerShell 5.1 (pwsh 7 compatible)
# Prepares winget, Git, pwsh, one agent CLI and the repository, then prints
# the two commands a person types to start the setup. It never elevates.
# Default (main branch, claude, no arguments):
#   irm https://raw.githubusercontent.com/hdmun/anything/main/pc-setup/bootstrap.ps1 | iex
# With arguments (e.g. another agent or a pushed branch):
#   & ([scriptblock]::Create((irm https://raw.githubusercontent.com/hdmun/anything/<branch>/pc-setup/bootstrap.ps1))) -Branch <branch> -Agent agy
[CmdletBinding()]
param(
    [string]$Source = 'https://github.com/hdmun/anything.git',
    [string]$Branch = '',
    [ValidateSet('claude', 'agy', 'codex')][string]$Agent = 'claude'
)

# Windows Package Manager 1.4.11071 (v1.4.11071) introduced --no-upgrade (#2655)
$script:MinWingetVersion = [version]'1.4.11071'

function New-Text {
    param([int[]]$Codes)
    $sb = [System.Text.StringBuilder]::new($Codes.Count)
    foreach ($c in $Codes) {
        [void]$sb.Append([char]$c)
    }
    return $sb.ToString()
}

function Test-AdminWindow {
    $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [System.Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-AnythingRepo {
    $val = [System.Environment]::GetEnvironmentVariable('ANYTHING_REPO', [System.EnvironmentVariableTarget]::User)
    if ($null -eq $val) {
        return ''
    }
    return [string]$val
}

function Get-DefaultRepoPath {
    return (Join-Path $HOME 'anything')
}

function Test-CommandExists {
    param([string]$Name)
    $cmd = Get-Command -Name $Name -CommandType Application -ErrorAction SilentlyContinue
    return ($null -ne $cmd)
}

function Invoke-Winget {
    param([string[]]$Arguments)
    & winget @Arguments | Out-Null
    return [int]$LASTEXITCODE
}

function Get-WingetVersion {
    $cmd = Get-Command 'winget' -ErrorAction SilentlyContinue
    if ($null -eq $cmd) {
        return $null
    }
    try {
        $raw = & $cmd.Source --version 2>$null
        if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($raw)) {
            return $null
        }
        $line = ($raw | Select-Object -First 1).ToString().Trim()
        if ($line -match '^v?(\d+\.\d+\.\d+(?:\.\d+)?)') {
            return [version]$Matches[1]
        }
        return $null
    } catch {
        return $null
    }
}

function Install-WingetFromGitHub {
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    $prevProgress = $ProgressPreference
    $ProgressPreference = 'SilentlyContinue'
    $workDir = Join-Path $env:TEMP ("pc-setup-winget-" + [System.Guid]::NewGuid().ToString())
    try {
        New-Item -Path $workDir -ItemType Directory -Force | Out-Null
        $headers = @{ 'User-Agent' = 'anything-pc-setup-bootstrap' }
        $downloadBase = 'https://github.com/microsoft/winget-cli/releases/latest/download'
        $bundleName = 'Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle'
        $depsName = 'DesktopAppInstaller_Dependencies.zip'

        $depsZipPath = Join-Path $workDir $depsName
        $bundlePath = Join-Path $workDir $bundleName
        $depsDir = Join-Path $workDir 'deps'

        Invoke-WebRequest -Uri "$downloadBase/$depsName" -OutFile $depsZipPath -UseBasicParsing -Headers $headers -ErrorAction Stop
        Invoke-WebRequest -Uri "$downloadBase/$bundleName" -OutFile $bundlePath -UseBasicParsing -Headers $headers -ErrorAction Stop

        Expand-Archive -LiteralPath $depsZipPath -DestinationPath $depsDir -Force

        $archRaw = if (-not [string]::IsNullOrEmpty($env:PROCESSOR_ARCHITEW6432)) { $env:PROCESSOR_ARCHITEW6432 } else { $env:PROCESSOR_ARCHITECTURE }
        $arch = switch ($archRaw) {
            'AMD64' { 'x64' }
            'ARM64' { 'arm64' }
            'x86'   { 'x86' }
            default { 'x64' }
        }
        $archDir = Join-Path $depsDir $arch
        if (Test-Path -LiteralPath $archDir -PathType Container) {
            $depPackages = Get-ChildItem -LiteralPath $archDir -Filter '*.appx' -File
            foreach ($dep in $depPackages) {
                Add-AppxPackage -Path $dep.FullName -ErrorAction Stop
            }
        }

        Add-AppxPackage -Path $bundlePath -ErrorAction Stop
    } finally {
        $ProgressPreference = $prevProgress
        if (Test-Path -LiteralPath $workDir) {
            Remove-Item -LiteralPath $workDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

function Register-WingetFamily {
    Add-AppxPackage -RegisterByFamilyName -MainPackage 'Microsoft.DesktopAppInstaller_8wekyb3d8bbwe' -ErrorAction Stop
}

# Reads the tag (e.g. v2.47.1.windows.1) from the redirect of releases/latest.
function Get-GitLatestTag {
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    $request = [System.Net.HttpWebRequest]::Create('https://github.com/git-for-windows/git/releases/latest')
    $request.Method = 'HEAD'
    $request.AllowAutoRedirect = $false
    $request.UserAgent = 'anything-pc-setup-bootstrap'
    $response = $request.GetResponse()
    try {
        $location = [string]$response.Headers['Location']
    } finally {
        $response.Close()
    }
    if ($location -match '/releases/tag/(v[^/?#]+)$') {
        return $Matches[1]
    }
    return ''
}

# Maps a Git for Windows tag to its 64-bit installer file name.
# v2.47.1.windows.1 -> Git-2.47.1-64-bit.exe, v2.47.1.windows.2 -> Git-2.47.1.2-64-bit.exe
function Get-GitInstallerName {
    param([string]$Tag)
    if ($Tag -notmatch '^v(\d+\.\d+\.\d+)\.windows\.(\d+)$') {
        throw "Unexpected Git for Windows tag: $Tag"
    }
    $version = $Matches[1]
    if ([int]$Matches[2] -gt 1) {
        $version = "$version.$($Matches[2])"
    }
    return "Git-$version-64-bit.exe"
}

function Install-GitForWindows {
    param([string]$Tag)
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    $prevProgress = $ProgressPreference
    $ProgressPreference = 'SilentlyContinue'
    $fileName = Get-GitInstallerName -Tag $Tag
    $installerPath = Join-Path $env:TEMP ("pc-setup-" + [System.Guid]::NewGuid().ToString() + "-" + $fileName)
    try {
        $uri = "https://github.com/git-for-windows/git/releases/download/$Tag/$fileName"
        Invoke-WebRequest -Uri $uri -OutFile $installerPath -UseBasicParsing -ErrorAction Stop
        $installDir = Join-Path $env:LOCALAPPDATA 'Programs\Git'
        $installerArgs = "/VERYSILENT /NORESTART /DIR=`"$installDir`" /o:PathOption=Cmd"
        $proc = Start-Process -FilePath $installerPath -ArgumentList $installerArgs -Wait -PassThru
        return [int]$proc.ExitCode
    } finally {
        $ProgressPreference = $prevProgress
        if (Test-Path -LiteralPath $installerPath) {
            Remove-Item -LiteralPath $installerPath -Force -ErrorAction SilentlyContinue
        }
    }
}

function Get-AgentInstallUrl {
    param([string]$Agent)
    switch ($Agent) {
        'claude' { return 'https://claude.ai/install.ps1' }
        'agy'    { return 'https://antigravity.google/cli/install.ps1' }
        'codex'  { return 'https://chatgpt.com/codex/install.ps1' }
    }
    throw "Unknown agent: $Agent"
}

# Runs the official install.ps1 in a child Windows PowerShell so that an `exit`
# inside the installer cannot end this session, and its exit code is kept.
function Install-AgentCli {
    param([string]$Agent)
    $url = Get-AgentInstallUrl -Agent $Agent
    $command = "`$ProgressPreference = 'SilentlyContinue'; irm $url | iex"
    $ps = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
    & $ps -NoProfile -ExecutionPolicy Bypass -Command $command | Out-Host
    return [int]$LASTEXITCODE
}

# Known install locations, used when the command is not on PATH yet.
# codex: defaultVisibleBinDir in https://chatgpt.com/codex/install.ps1
function Get-AgentKnownPath {
    param([string]$Agent)
    switch ($Agent) {
        'claude' { return (Join-Path $env:USERPROFILE '.local\bin\claude.exe') }
        'agy'    { return (Join-Path $env:LOCALAPPDATA 'agy\bin\agy.exe') }
        'codex'  { return (Join-Path $env:LOCALAPPDATA 'Programs\OpenAI\Codex\bin\codex.exe') }
    }
    return ''
}

# Returns the command name when it is on PATH, the full path of the known
# install location when the executable is there, and '' otherwise.
function Get-AgentExePath {
    param([string]$Agent)
    if (Test-CommandExists -Name $Agent) {
        return $Agent
    }
    $known = Get-AgentKnownPath -Agent $Agent
    if (-not [string]::IsNullOrEmpty($known) -and (Test-Path -LiteralPath $known -PathType Leaf)) {
        return $known
    }
    return ''
}

function Invoke-Git {
    param([string[]]$Arguments)
    & git @Arguments | Out-Null
    return [int]$LASTEXITCODE
}

function Update-SessionPath {
    $machinePath = [System.Environment]::GetEnvironmentVariable('Path', [System.EnvironmentVariableTarget]::Machine)
    $userPath = [System.Environment]::GetEnvironmentVariable('Path', [System.EnvironmentVariableTarget]::User)
    $parts = @()
    if (-not [string]::IsNullOrEmpty($machinePath)) { $parts += $machinePath }
    if (-not [string]::IsNullOrEmpty($userPath)) { $parts += $userPath }
    $env:Path = $parts -join ';'
}

function Invoke-Bootstrap {
    param(
        [string]$Source = 'https://github.com/hdmun/anything.git',
        [string]$Branch = '',
        [string]$Agent = 'claude'
    )

    $ProgressPreference = 'SilentlyContinue'
    $stageName     = New-Text @(0xBD80,0xD2B8,0xC2A4,0xD2B8,0xB7A9) # bootstrap
    $statusSame    = New-Text @(0xADF8,0xB300,0xB85C)               # same
    $statusChanged = New-Text @(0xBC14,0xAFC8)                      # changed
    $statusFail    = New-Text @(0xC2E4,0xD328)                      # fail
    $textInstall   = New-Text @(0x0020,0xC124,0xCE58)               # " install"
    $textExitCode  = New-Text @(0x0020,0xC885,0xB8CC,0x0020,0xCF54,0xB4DC,0x0020) # " exit code "
    $textAfter     = New-Text @(0xC124,0xCE58,0x0020,0xB4A4,0xC5D0,0xB3C4,0x0020) # "after install "
    $textMissing   = New-Text @(0x0020,0xC774,0x0020,0xC5C6,0xB2E4)  # " is missing"

    # 1. Admin window check
    if (Test-AdminWindow) {
        Write-Host (New-Text @(0xBD80,0xD2B8,0xC2A4,0xD2B8,0xB7A9,0xC740,0x0020,0xC77C,0xBC18,0x0020,0xAD8C,0xD55C,0x0020,0xCC3D,0xC5D0,0xC11C,0x0020,0xC2E4,0xD589,0xD55C,0xB2E4))
        return 2
    }

    $addResult = {
        param([string]$Id, [string]$Status, [string]$Detail = '')
        $lineText = if ($Status -eq $statusFail) { "${statusFail}: $Detail" } else { $Status }
        Write-Host "[$stageName] ${Id}: $lineText"
    }
    $exitCodeDetail = {
        param([string]$What, [int]$Code)
        return "$What$textInstall$textExitCode$Code"
    }
    $missingDetail = {
        param([string]$Name)
        return "$textAfter$Name$textMissing"
    }

    # 2. winget
    $minVersion = if ($null -ne $script:MinWingetVersion) { $script:MinWingetVersion } else { [version]'1.4.11071' }
    try {
        $wingetVer = Get-WingetVersion
    } catch {
        & $addResult 'winget' $statusFail $_.Exception.Message
        return 1
    }

    if ($null -ne $wingetVer -and $wingetVer -ge $minVersion) {
        & $addResult 'winget' $statusSame
    } else {
        $lastWingetError = ''
        try {
            Register-WingetFamily
            Update-SessionPath
            $wingetVer = Get-WingetVersion
        } catch {
            $lastWingetError = $_.Exception.Message
        }

        if ($null -eq $wingetVer -or $wingetVer -lt $minVersion) {
            try {
                Install-WingetFromGitHub
                Update-SessionPath
                $wingetVer = Get-WingetVersion
            } catch {
                $lastWingetError = $_.Exception.Message
            }
        }

        if ($null -ne $wingetVer -and $wingetVer -ge $minVersion) {
            & $addResult 'winget' $statusChanged
        } else {
            if ([string]::IsNullOrWhiteSpace($lastWingetError)) {
                $lastWingetError = "winget $minVersion+ unavailable"
            }
            & $addResult 'winget' $statusFail $lastWingetError
            return 1
        }
    }

    # 3. Git (user scope, no elevation)
    if (Test-CommandExists -Name 'git') {
        & $addResult 'Git' $statusSame
    } else {
        try {
            $tag = Get-GitLatestTag
        } catch {
            & $addResult 'Git' $statusFail $_.Exception.Message
            return 1
        }
        if ([string]::IsNullOrWhiteSpace($tag)) {
            & $addResult 'Git' $statusFail (New-Text @(0xCD5C,0xC2E0,0x0020,0xD0DC,0xADF8,0xB97C,0x0020,0xC77D,0xC9C0,0x0020,0xBABB,0xD588,0xB2E4)) # latest tag unreadable
            return 1
        }
        try {
            $gitInstallCode = Install-GitForWindows -Tag $tag
        } catch {
            & $addResult 'Git' $statusFail $_.Exception.Message
            return 1
        }
        if ($gitInstallCode -ne 0) {
            & $addResult 'Git' $statusFail (& $exitCodeDetail 'Git' $gitInstallCode)
            return 1
        }
        Update-SessionPath
        if (-not (Test-CommandExists -Name 'git')) {
            & $addResult 'Git' $statusFail (& $missingDetail 'git')
            return 1
        }
        & $addResult 'Git' $statusChanged
    }

    # 4. pwsh (msixbundle, user scope)
    if (Test-CommandExists -Name 'pwsh') {
        & $addResult 'Microsoft.PowerShell' $statusSame
    } else {
        try {
            $pwshInstallCode = Invoke-Winget -Arguments @('install', '--id', 'Microsoft.PowerShell', '--source', 'winget', '--exact', '--silent', '--accept-package-agreements', '--accept-source-agreements')
        } catch {
            & $addResult 'Microsoft.PowerShell' $statusFail $_.Exception.Message
            return 1
        }
        if ($pwshInstallCode -ne 0) {
            & $addResult 'Microsoft.PowerShell' $statusFail (& $exitCodeDetail 'pwsh' $pwshInstallCode)
            return 1
        }
        Update-SessionPath
        if (-not (Test-CommandExists -Name 'pwsh')) {
            & $addResult 'Microsoft.PowerShell' $statusFail (& $missingDetail 'pwsh')
            return 1
        }
        & $addResult 'Microsoft.PowerShell' $statusChanged
    }

    # 5. Agent CLI (PATH is left to the setup)
    $agentExe = Get-AgentExePath -Agent $Agent
    if (-not [string]::IsNullOrEmpty($agentExe)) {
        & $addResult $Agent $statusSame
    } else {
        try {
            $agentInstallCode = Install-AgentCli -Agent $Agent
        } catch {
            & $addResult $Agent $statusFail $_.Exception.Message
            return 1
        }
        if ($agentInstallCode -ne 0) {
            & $addResult $Agent $statusFail (& $exitCodeDetail $Agent $agentInstallCode)
            return 1
        }
        Update-SessionPath
        $agentExe = Get-AgentExePath -Agent $Agent
        if ([string]::IsNullOrEmpty($agentExe)) {
            & $addResult $Agent $statusFail (& $missingDetail $Agent)
            return 1
        }
        & $addResult $Agent $statusChanged
    }

    # 6. Clone
    $anythingRepo = Get-AnythingRepo
    $repoPath = if (-not [string]::IsNullOrWhiteSpace($anythingRepo)) { $anythingRepo } else { Get-DefaultRepoPath }
    $setupDocPath = Join-Path $repoPath 'pc-setup\SETUP.md'
    if (Test-Path -LiteralPath $repoPath) {
        if (Test-Path -LiteralPath $setupDocPath -PathType Leaf) {
            & $addResult 'clone' $statusSame
        } else {
            $missingSetupDetail = "$repoPath" + (New-Text @(0x0020,0xC5D0,0x0020,0xC14B,0xC5C5,0xC774,0x0020,0xC5C6,0xB2E4))
            & $addResult 'clone' $statusFail $missingSetupDetail
            return 1
        }
    } else {
        $gitArgs = if (-not [string]::IsNullOrWhiteSpace($Branch)) {
            @('clone', '-b', $Branch, $Source, $repoPath)
        } else {
            @('clone', $Source, $repoPath)
        }
        try {
            $gitCode = Invoke-Git -Arguments $gitArgs
        } catch {
            & $addResult 'clone' $statusFail $_.Exception.Message
            return 1
        }

        if ($gitCode -eq 0) {
            & $addResult 'clone' $statusChanged
        } else {
            & $addResult 'clone' $statusFail ('git clone' + $textExitCode + $gitCode)
            return 1
        }
    }

    # 7. The two commands a person types
    $setupDir = Join-Path $repoPath 'pc-setup'
    $cdLine = if ($setupDir.Contains(' ')) { "cd `"$setupDir`"" } else { "cd $setupDir" }
    $agentCall = if ($agentExe.Contains(' ')) { "& `"$agentExe`"" } else { $agentExe }
    $prompt = New-Text @(0x0053,0x0045,0x0054,0x0055,0x0050,0x002E,0x006D,0x0064,0x0020,0xB97C,0x0020,0xC77D,0xACE0,0x0020,0xC14B,0xC5C5,0xD574) # read SETUP.md and set up
    $agentFlags = switch ($Agent) {
        'agy'   { '--dangerously-skip-permissions -i' }
        'codex' { '--yolo' }
        default { '--dangerously-skip-permissions' }
    }
    Write-Host $cdLine
    Write-Host "$agentCall $agentFlags `"$prompt`""
    return 0
}

$code = Invoke-Bootstrap -Source $Source -Branch $Branch -Agent $Agent
if ($PSCommandPath) { exit $code } else { $global:LASTEXITCODE = $code }
