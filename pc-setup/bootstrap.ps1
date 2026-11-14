# pc-setup/bootstrap.ps1 - Windows PowerShell 5.1 (pwsh 7 compatible)
# Default (main branch, no arguments):
#   irm https://raw.githubusercontent.com/hdmun/anything/main/pc-setup/bootstrap.ps1 | iex
# With arguments (e.g. testing a pushed branch):
#   & ([scriptblock]::Create((irm https://raw.githubusercontent.com/hdmun/anything/<branch>/pc-setup/bootstrap.ps1))) -Branch <branch> -Skip <Id>,<Id>
[CmdletBinding()]
param(
    [string]$Source = 'https://github.com/hdmun/anything.git',
    [string]$Branch = '',
    [string[]]$Skip = @(),
    [string]$ResultPath = '',
    [string]$SetupResultPath = ''
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
        $release = Invoke-RestMethod -Uri 'https://api.github.com/repos/microsoft/winget-cli/releases/latest' -Headers $headers -ErrorAction Stop

        $bundleAsset = $release.assets | Where-Object { $_.name -eq 'Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle' } | Select-Object -First 1
        $depsAsset = $release.assets | Where-Object { $_.name -eq 'DesktopAppInstaller_Dependencies.zip' } | Select-Object -First 1
        if ($null -eq $bundleAsset -or $null -eq $depsAsset) {
            throw 'Missing expected winget-cli release assets'
        }

        $depsZipPath = Join-Path $workDir 'DesktopAppInstaller_Dependencies.zip'
        $bundlePath = Join-Path $workDir 'Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle'
        $depsDir = Join-Path $workDir 'deps'

        Invoke-WebRequest -Uri $depsAsset.browser_download_url -OutFile $depsZipPath -UseBasicParsing -Headers $headers -ErrorAction Stop
        Invoke-WebRequest -Uri $bundleAsset.browser_download_url -OutFile $bundlePath -UseBasicParsing -Headers $headers -ErrorAction Stop

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

function Invoke-ElevatedInstall {
    param([string[]]$Ids)

    $errRejected = New-Text @(0xC2B9,0xACA9,0x0020,0xAC70,0xBD80,0xB428) # elevation rejected
    $errNoResult = New-Text @(0xC2B9,0xACA9,0x0020,0xB2E8,0xACC4,0x0020,0xACB0,0xACFC,0x0020,0xC5C6,0xC74C) # elevation no result

    $guid = [System.Guid]::NewGuid().ToString()
    $tempFile = Join-Path $env:TEMP "pc-setup-bootstrap-$guid.json"

    $escapedTemp = $tempFile.Replace("'", "''")
    $escapedIds = foreach ($pkgId in $Ids) { "'" + $pkgId.Replace("'", "''") + "'" }
    $idsLiteral = '@(' + ($escapedIds -join ',') + ')'

    $childScript = @"
`$codes = @{}
foreach (`$id in $idsLiteral) {
    & winget install --id `$id -e --scope machine --no-upgrade --source winget --accept-package-agreements --accept-source-agreements --disable-interactivity
    `$codes[`$id] = [int]`$LASTEXITCODE
}
`$json = ConvertTo-Json -InputObject `$codes -Compress
[System.IO.File]::WriteAllText('$escapedTemp', `$json, [System.Text.Encoding]::UTF8)
"@

    $bytes = [System.Text.Encoding]::Unicode.GetBytes($childScript)
    $b64 = [System.Convert]::ToBase64String($bytes)

    $codes = @{}
    $errorMsg = ''

    try {
        try {
            Start-Process -FilePath 'powershell.exe' -Verb RunAs -Wait -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-EncodedCommand', $b64
        } catch {
            return @{
                Requested = 1
                Codes     = @{}
                Error     = $errRejected
            }
        }

        if (-not (Test-Path -LiteralPath $tempFile -PathType Leaf)) {
            $errorMsg = $errNoResult
        } else {
            $content = Get-Content -LiteralPath $tempFile -Raw -Encoding UTF8
            if ([string]::IsNullOrWhiteSpace($content)) {
                $errorMsg = $errNoResult
            } else {
                try {
                    $parsed = $content | ConvertFrom-Json
                    if ($null -eq $parsed) {
                        $errorMsg = $errNoResult
                    } else {
                        foreach ($prop in $parsed.PSObject.Properties) {
                            $codes[$prop.Name] = [int]$prop.Value
                        }
                    }
                } catch {
                    $errorMsg = $errNoResult
                }
            }
        }

        return @{
            Requested = 1
            Codes     = $codes
            Error     = $errorMsg
        }
    } finally {
        if (Test-Path -LiteralPath $tempFile) {
            Remove-Item -LiteralPath $tempFile -Force -ErrorAction SilentlyContinue
        }
    }
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

function Start-SetupScript {
    param(
        [string]$RepoPath,
        [string[]]$Skip = @(),
        [string]$ResultPath = ''
    )

    $pwshCmd = Get-Command 'pwsh' -ErrorAction SilentlyContinue
    $pwshExe = if ($null -ne $pwshCmd) {
        $pwshCmd.Source
    } else {
        Join-Path $env:ProgramFiles 'PowerShell\7\pwsh.exe'
    }

    $setupFile = Join-Path $RepoPath 'pc-setup\setup.ps1'
    $pwshArgs = [System.Collections.Generic.List[string]]::new()
    $pwshArgs.Add('-NoProfile')
    $pwshArgs.Add('-File')
    $pwshArgs.Add($setupFile)

    $skipItems = [System.Collections.Generic.List[string]]::new()
    if ($null -ne $Skip) {
        foreach ($item in $Skip) {
            foreach ($part in ($item -split ',')) {
                $trimmed = $part.Trim()
                if ($trimmed -ne '') {
                    $skipItems.Add($trimmed)
                }
            }
        }
    }
    if ($skipItems.Count -gt 0) {
        $pwshArgs.Add('-Skip')
        $pwshArgs.Add(($skipItems -join ','))
    }

    if (-not [string]::IsNullOrWhiteSpace($ResultPath)) {
        $pwshArgs.Add('-ResultPath')
        $pwshArgs.Add($ResultPath)
    }

    $argArray = [string[]]$pwshArgs.ToArray()
    & $pwshExe @argArray | Out-Default
    return [int]$LASTEXITCODE
}

function Invoke-Bootstrap {
    param(
        [string]$Source = 'https://github.com/hdmun/anything.git',
        [string]$Branch = '',
        [string[]]$Skip = @(),
        [string]$ResultPath = '',
        [string]$SetupResultPath = ''
    )

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $stageName     = New-Text @(0xBD80,0xD2B8,0xC2A4,0xD2B8,0xB7A9) # bootstrap
    $statusSame    = New-Text @(0xADF8,0xB300,0xB85C)               # same
    $statusChanged = New-Text @(0xBC14,0xAFC8)                      # changed
    $statusTodo    = New-Text @(0xD560,0x0020,0xC77C)               # todo
    $statusFail    = New-Text @(0xC2E4,0xD328)                      # fail

    # 1. Admin window check
    if (Test-AdminWindow) {
        Write-Host (New-Text @(0xBD80,0xD2B8,0xC2A4,0xD2B8,0xB7A9,0xC740,0x0020,0xC77C,0xBC18,0x0020,0xAD8C,0xD55C,0x0020,0xCC3D,0xC5D0,0xC11C,0x0020,0xC2E4,0xD589,0xD55C,0xB2E4))
        return 2
    }

    $results = [System.Collections.Generic.List[object]]::new()
    $elevationRequests = 0

    $addResult = {
        param([string]$Id, [string]$Status, [string]$Detail = '')
        $obj = [pscustomobject]@{
            Stage  = $stageName
            Id     = $Id
            Status = $Status
            Detail = $Detail
        }
        $results.Add($obj)
        $lineText = if ($Status -eq $statusSame) {
            $statusSame
        } elseif ($Status -eq $statusChanged) {
            if ([string]::IsNullOrEmpty($Detail)) { $statusChanged } else { "$statusChanged ($Detail)" }
        } elseif ($Status -eq $statusTodo) {
            "${statusTodo}: $Detail"
        } elseif ($Status -eq $statusFail) {
            "${statusFail}: $Detail"
        } else {
            $Status
        }
        Write-Host "[$stageName] ${Id}: $lineText"
    }

    $writeSummaryAndJson = {
        $elapsed = $stopwatch.Elapsed
        $totalHours = [int][Math]::Floor($elapsed.TotalHours)
        $durationStr = if ($totalHours -ge 1) {
            "${totalHours}:$($elapsed.Minutes.ToString('d2')):$($elapsed.Seconds.ToString('d2'))"
        } else {
            "$($elapsed.Minutes.ToString('d2')):$($elapsed.Seconds.ToString('d2'))"
        }
        $elevLabel = (New-Text @(0xBD80,0xD2B8,0xC2A4,0xD2B8,0xB7A9,0x0020,0xC2B9,0xACA9,0x0020,0xC694,0xCCAD,0x003A,0x0020)) + $elevationRequests + (New-Text @(0xD68C))
        $timeLabel = (New-Text @(0xBD80,0xD2B8,0xC2A4,0xD2B8,0xB7A9,0x0020,0xAC78,0xB9B0,0x0020,0xC2DC,0xAC04,0x003A,0x0020)) + $durationStr
        Write-Host $elevLabel
        Write-Host $timeLabel

        if (-not [string]::IsNullOrEmpty($ResultPath)) {
            try {
                $jsonObj = [ordered]@{
                    Check             = $false
                    ElevationRequests = $elevationRequests
                    DurationSeconds   = [Math]::Round($elapsed.TotalSeconds, 1)
                    Results           = [object[]]$results.ToArray()
                }
                $jsonText = $jsonObj | ConvertTo-Json -Depth 5
                [System.IO.File]::WriteAllText($ResultPath, $jsonText, [System.Text.Encoding]::UTF8)
            } catch {
                $warnPrefix = New-Text @(0xACB0,0xACFC,0x0020,0x004A,0x0053,0x004F,0x004E,0x0020,0xC4F0,0xAE30,0x0020,0xC2E4,0xD328,0x003A,0x0020)
                Write-Warning ($warnPrefix + $_.Exception.Message)
            }
        }
    }

    # 2. Repository path
    $anythingRepo = Get-AnythingRepo
    $repoPath = $null
    if (-not [string]::IsNullOrWhiteSpace($anythingRepo)) {
        $candidateSetup = Join-Path $anythingRepo 'pc-setup\setup.ps1'
        if (Test-Path -LiteralPath $candidateSetup -PathType Leaf) {
            $repoPath = $anythingRepo
        }
    }
    if ($null -eq $repoPath) {
        $repoPath = Get-DefaultRepoPath
    }

    # 3. Ensure winget
    $minVersion = if ($null -ne $script:MinWingetVersion) { $script:MinWingetVersion } else { [version]'1.4.11071' }
    try {
        $wingetVer = Get-WingetVersion
    } catch {
        & $addResult 'winget' $statusFail $_.Exception.Message
        & $writeSummaryAndJson
        return 1
    }

    if ($null -ne $wingetVer -and $wingetVer -ge $minVersion) {
        & $addResult 'winget' $statusSame ''
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
            & $addResult 'winget' $statusChanged ''
        } else {
            if ([string]::IsNullOrWhiteSpace($lastWingetError)) {
                $lastWingetError = "winget $minVersion+ unavailable"
            }
            & $addResult 'winget' $statusFail $lastWingetError
            & $writeSummaryAndJson
            return 1
        }
    }

    # 4. Ensure Git & pwsh
    $targetIds = @('Git.Git', 'Microsoft.PowerShell')
    $present = @{}
    $missing = [System.Collections.Generic.List[string]]::new()

    try {
        foreach ($pkgId in $targetIds) {
            $checkCode = Invoke-Winget -Arguments @('list', '--id', $pkgId, '-e', '--accept-source-agreements')
            if ($checkCode -eq 0) {
                $present[$pkgId] = $true
            } else {
                $missing.Add($pkgId)
            }
        }
    } catch {
        foreach ($pkgId in $targetIds) {
            if ($present.ContainsKey($pkgId)) {
                & $addResult $pkgId $statusSame ''
            } else {
                & $addResult $pkgId $statusFail $_.Exception.Message
            }
        }
        & $writeSummaryAndJson
        return 1
    }

    if ($missing.Count -eq 0) {
        foreach ($pkgId in $targetIds) {
            & $addResult $pkgId $statusSame ''
        }
    } else {
        $elevOutcome = $null
        try {
            $elevOutcome = Invoke-ElevatedInstall -Ids ([string[]]$missing.ToArray())
        } catch {
            $elevationRequests++
            foreach ($pkgId in $targetIds) {
                if ($present.ContainsKey($pkgId)) {
                    & $addResult $pkgId $statusSame ''
                } else {
                    & $addResult $pkgId $statusFail $_.Exception.Message
                }
            }
            & $writeSummaryAndJson
            return 1
        }

        $elevationRequests += [int]$elevOutcome.Requested
        $hasStep4Fail = $false
        $hasStep4Todo = $false

        $rebootDetail = New-Text @(0xC7AC,0xBD80,0xD305,0x0020,0xD6C4,0x0020,0xBD80,0xD2B8,0xC2A4,0xD2B8,0xB7A9,0x0020,0xB2E4,0xC2DC,0x0020,0xC2E4,0xD589)
        $noResultDetail = New-Text @(0xC2B9,0xACA9,0x0020,0xB2E8,0xACC4,0x0020,0xACB0,0xACFC,0x0020,0xC5C6,0xC74C)
        $wingetFailPrefix = 'winget ' + (New-Text @(0xC885,0xB8CC,0x0020,0xCF54,0xB4DC)) + ' '

        foreach ($pkgId in $targetIds) {
            if ($present.ContainsKey($pkgId)) {
                & $addResult $pkgId $statusSame ''
                continue
            }

            if (-not [string]::IsNullOrEmpty($elevOutcome.Error)) {
                & $addResult $pkgId $statusFail $elevOutcome.Error
                $hasStep4Fail = $true
                continue
            }

            $codesDict = $elevOutcome.Codes
            $hasKey = ($null -ne $codesDict) -and (
                (($codesDict -is [System.Collections.IDictionary]) -and $codesDict.Contains($pkgId)) -or
                ($null -ne $codesDict.PSObject.Properties[$pkgId])
            )
            if (-not $hasKey) {
                & $addResult $pkgId $statusFail $noResultDetail
                $hasStep4Fail = $true
                continue
            }

            $installCode = if ($codesDict -is [System.Collections.IDictionary]) { $codesDict[$pkgId] } else { $codesDict.$pkgId }
            $hexCode = '0x{0:X8}' -f ([uint32]([int64]$installCode -band 0xFFFFFFFFL))
            if ([int64]$installCode -eq 0) {
                & $addResult $pkgId $statusChanged ''
            } elseif ($hexCode -eq '0x8A150109') {
                & $addResult $pkgId $statusTodo $rebootDetail
                $hasStep4Todo = $true
            } else {
                & $addResult $pkgId $statusFail ($wingetFailPrefix + $hexCode)
                $hasStep4Fail = $true
            }
        }

        if ($hasStep4Fail -or $hasStep4Todo) {
            & $writeSummaryAndJson
            if ($hasStep4Fail) { return 1 } else { return 0 }
        }

        Update-SessionPath
    }

    # 5. Clone
    $setupScriptPath = Join-Path $repoPath 'pc-setup\setup.ps1'
    if (Test-Path -LiteralPath $repoPath) {
        if (Test-Path -LiteralPath $setupScriptPath -PathType Leaf) {
            & $addResult 'clone' $statusSame ''
        } else {
            $missingSetupDetail = "$repoPath" + (New-Text @(0x0020,0xC5D0,0x0020,0xC14B,0xC5C5,0xC774,0x0020,0xC5C6,0xB2E4))
            & $addResult 'clone' $statusFail $missingSetupDetail
            & $writeSummaryAndJson
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
            & $writeSummaryAndJson
            return 1
        }

        if ($gitCode -eq 0) {
            & $addResult 'clone' $statusChanged ''
        } else {
            $gitFailDetail = 'git clone ' + (New-Text @(0xC885,0xB8CC,0x0020,0xCF54,0xB4DC)) + " $gitCode"
            & $addResult 'clone' $statusFail $gitFailDetail
            & $writeSummaryAndJson
            return 1
        }
    }

    # 6. Summary & JSON
    & $writeSummaryAndJson

    # 7. Setup
    try {
        $setupCode = Start-SetupScript -RepoPath $repoPath -Skip $Skip -ResultPath $SetupResultPath
        return [int]$setupCode
    } catch {
        & $addResult 'setup' $statusFail $_.Exception.Message
        return 1
    }
}

$code = Invoke-Bootstrap -Source $Source -Branch $Branch -Skip $Skip -ResultPath $ResultPath -SetupResultPath $SetupResultPath
if ($PSCommandPath) { exit $code } else { $global:LASTEXITCODE = $code }
