Import-Module (Join-Path $PSScriptRoot 'EnvPath.psm1') -Force

function Invoke-ExternalCommand {
    # 외부 명령을 부르고 -> @{ ExitCode = <int>; Output = <string[]> }. 명령이 없으면 ExitCode = $null.
    param(
        [Parameter(Mandatory)][string]$CommandName,
        [Parameter(Mandatory)][string[]]$Arguments
    )

    $cmd = Get-Command $CommandName -ErrorAction SilentlyContinue
    if ($null -eq $cmd) {
        return @{ ExitCode = $null; Output = [string[]]@() }
    }

    $rawOutput = & $cmd.Source @Arguments 2>&1
    $exitCode = $LASTEXITCODE
    $lines = [System.Collections.Generic.List[string]]::new()
    if ($null -ne $rawOutput) {
        foreach ($item in @($rawOutput)) {
            $lines.Add($item.ToString())
        }
    }

    return @{ ExitCode = [int]$exitCode; Output = [string[]]$lines.ToArray() }
}

function Invoke-Nvm {
    param([Parameter(Mandatory)][string[]]$Arguments)
    return Invoke-ExternalCommand -CommandName 'nvm' -Arguments $Arguments
}

function Invoke-Pnpm {
    param([Parameter(Mandatory)][string[]]$Arguments)
    return Invoke-ExternalCommand -CommandName 'pnpm' -Arguments $Arguments
}

function Invoke-Go {
    param([Parameter(Mandatory)][string[]]$Arguments)
    return Invoke-ExternalCommand -CommandName 'go' -Arguments $Arguments
}

function Get-UserEnv {
    param([Parameter(Mandatory)][string]$Name)
    return [System.Environment]::GetEnvironmentVariable($Name, [System.EnvironmentVariableTarget]::User)
}

function Set-UserEnv {
    param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][string]$Value)
    [System.Environment]::SetEnvironmentVariable($Name, $Value, [System.EnvironmentVariableTarget]::User)
}

function Get-SemverStrings {
    # 출력 줄들에서 v?X.Y.Z 형식의 버전 문자열을 앞의 'v' 를 떼고 뽑아낸다.
    param([string[]]$Lines)

    $versions = [System.Collections.Generic.List[string]]::new()
    if ($null -eq $Lines) {
        return [string[]]@()
    }

    foreach ($line in $Lines) {
        if ([string]::IsNullOrWhiteSpace($line)) {
            continue
        }
        $matches = [regex]::Matches($line, 'v?(\d+\.\d+\.\d+)')
        foreach ($m in $matches) {
            $versions.Add($m.Groups[1].Value)
        }
    }

    return [string[]]$versions.ToArray()
}

function Invoke-NvmApp {
    # -> @{ Status; Detail }
    param([Parameter(Mandatory)]$Entry, [bool]$Check)

    Update-SessionPath

    $verResult = Invoke-Nvm -Arguments @('version')
    $nvmVersions = @(if ($null -ne $verResult.ExitCode -and $verResult.ExitCode -eq 0) {
        Get-SemverStrings -Lines $verResult.Output
    })
    $hasNvmV2 = ($nvmVersions.Count -gt 0 -and $nvmVersions[0].StartsWith('2.', [System.StringComparison]::Ordinal))
    if (-not $hasNvmV2) {
        if ($Check) {
            return @{ Status = '다름'; Detail = 'nvm v2 없음' }
        }
        return @{ Status = '실패'; Detail = 'nvm v2 가 없다' }
    }

    $nodeLine = [string]$Entry.NodeLine
    $listResult = Invoke-Nvm -Arguments @('list')
    if ($null -eq $listResult.ExitCode) {
        if ($Check) {
            return @{ Status = '다름'; Detail = 'nvm v2 없음' }
        }
        return @{ Status = '실패'; Detail = 'nvm v2 가 없다' }
    }
    if ($listResult.ExitCode -ne 0) {
        return @{ Status = '실패'; Detail = "nvm list 종료 코드 $($listResult.ExitCode)" }
    }

    $installed = @(Get-SemverStrings -Lines $listResult.Output)
    $prefix = "$nodeLine."
    $found = $false
    foreach ($ver in $installed) {
        if ($ver.StartsWith($prefix, [System.StringComparison]::Ordinal)) {
            $found = $true
            break
        }
    }

    if ($found) {
        return @{ Status = '그대로'; Detail = '' }
    }

    if ($Check) {
        return @{ Status = '다름'; Detail = "Node $nodeLine 줄 없음" }
    }

    $installResult = Invoke-Nvm -Arguments @('install', $nodeLine)
    if ($null -eq $installResult.ExitCode -or $installResult.ExitCode -ne 0) {
        $code = if ($null -eq $installResult.ExitCode) { 'null' } else { $installResult.ExitCode }
        return @{ Status = '실패'; Detail = "nvm install $nodeLine 종료 코드 $code" }
    }

    $defaultResult = Invoke-Nvm -Arguments @('default')
    if ($null -eq $defaultResult.ExitCode -or $defaultResult.ExitCode -ne 0) {
        $defaultCode = if ($null -eq $defaultResult.ExitCode) { 'null' } else { $defaultResult.ExitCode }
        return @{ Status = '실패'; Detail = "nvm default 종료 코드 $defaultCode" }
    }
    $defaultVersions = @(Get-SemverStrings -Lines $defaultResult.Output)

    if ($defaultVersions.Count -eq 0) {
        $useResult = Invoke-Nvm -Arguments @('use', $nodeLine)
        if ($null -eq $useResult.ExitCode -or $useResult.ExitCode -ne 0) {
            $useCode = if ($null -eq $useResult.ExitCode) { 'null' } else { $useResult.ExitCode }
            return @{ Status = '실패'; Detail = "nvm use $nodeLine 종료 코드 $useCode" }
        }
    }

    Update-SessionPath
    return @{ Status = '바꿈'; Detail = '' }
}

function Invoke-PnpmApp {
    # -> @{ Status; Detail }
    param([Parameter(Mandatory)]$Entry, [bool]$Check)

    $changed = $false
    $pnpmHome = Get-UserEnv -Name 'PNPM_HOME'
    if ([string]::IsNullOrWhiteSpace($pnpmHome)) {
        if ($Check) {
            return @{ Status = '다름'; Detail = 'PNPM_HOME 없음' }
        }
        $pnpmHome = [System.Environment]::ExpandEnvironmentVariables('%LOCALAPPDATA%\pnpm')
        Set-UserEnv -Name 'PNPM_HOME' -Value $pnpmHome
        $env:PNPM_HOME = $pnpmHome
        $changed = $true
    }

    if ($Check) {
        $userPath = Get-UserEnv -Name 'Path'
        $normalizedTarget = $pnpmHome.TrimEnd('\')
        $inPath = $false
        if (-not [string]::IsNullOrWhiteSpace($userPath)) {
            foreach ($piece in ($userPath -split ';')) {
                if (-not [string]::IsNullOrWhiteSpace($piece)) {
                    $expanded = [System.Environment]::ExpandEnvironmentVariables($piece).TrimEnd('\')
                    if ($expanded -ieq $normalizedTarget) {
                        $inPath = $true
                        break
                    }
                }
            }
        }
        if (-not $inPath) {
            return @{ Status = '다름'; Detail = 'PNPM_HOME 이 PATH 에 없음' }
        }
    } else {
        if (Add-UserPath -Path $pnpmHome) {
            $changed = $true
        }
    }

    Update-SessionPath

    $lsResult = Invoke-Pnpm -Arguments @('ls', '-g', '--json')
    if ($null -eq $lsResult.ExitCode) {
        if ($Check) {
            return @{ Status = '다름'; Detail = 'pnpm 없음' }
        }
        return @{ Status = '실패'; Detail = 'pnpm 이 없다' }
    }
    if ($lsResult.ExitCode -ne 0) {
        return @{ Status = '실패'; Detail = "pnpm ls -g --json 종료 코드 $($lsResult.ExitCode)" }
    }

    $id = [string]$Entry.Id
    $installed = $false
    $jsonText = ($lsResult.Output -join "`n").Trim()
    if (-not [string]::IsNullOrEmpty($jsonText)) {
        $parsed = @($jsonText | ConvertFrom-Json)
        if ($parsed.Count -gt 0 -and $null -ne $parsed[0]) {
            $depsProp = $parsed[0].PSObject.Properties['dependencies']
            if ($null -ne $depsProp -and $null -ne $depsProp.Value) {
                $depNames = @($depsProp.Value.PSObject.Properties | ForEach-Object { $_.Name })
                if ($depNames -ccontains $id) {
                    $installed = $true
                }
            }
        }
    }

    if ($installed) {
        if ($changed) {
            return @{ Status = '바꿈'; Detail = '' }
        }
        return @{ Status = '그대로'; Detail = '' }
    }

    if ($Check) {
        return @{ Status = '다름'; Detail = '설치 안 됨' }
    }

    $addResult = Invoke-Pnpm -Arguments @('add', '-g', $id)
    if ($null -eq $addResult.ExitCode -or $addResult.ExitCode -ne 0) {
        $code = if ($null -eq $addResult.ExitCode) { 'null' } else { $addResult.ExitCode }
        return @{ Status = '실패'; Detail = "pnpm add -g $id 종료 코드 $code" }
    }

    return @{ Status = '바꿈'; Detail = '' }
}

function Invoke-GoApp {
    # -> @{ Status; Detail }
    param([Parameter(Mandatory)]$Entry, [bool]$Check)

    Update-SessionPath

    $envResult = Invoke-Go -Arguments @('env', 'GOPATH')
    if ($null -eq $envResult.ExitCode) {
        if ($Check) {
            return @{ Status = '다름'; Detail = 'go 없음' }
        }
        return @{ Status = '실패'; Detail = 'go 가 없다' }
    }
    if ($envResult.ExitCode -ne 0) {
        return @{ Status = '실패'; Detail = "go env GOPATH 종료 코드 $($envResult.ExitCode)" }
    }

    $firstLine = ($envResult.Output | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -First 1)
    if ([string]::IsNullOrWhiteSpace($firstLine)) {
        return @{ Status = '실패'; Detail = 'go env GOPATH 가 비어 있다' }
    }
    $gopath = ($firstLine.Trim() -split ';')[0].Trim()

    $id = [string]$Entry.Id
    $leaf = ($id -split '/')[-1]
    $exePath = Join-Path $gopath 'bin' "$leaf.exe"

    if (Test-Path -LiteralPath $exePath -PathType Leaf) {
        return @{ Status = '그대로'; Detail = '' }
    }

    if ($Check) {
        return @{ Status = '다름'; Detail = '설치 안 됨' }
    }

    $target = "$id@latest"
    $installResult = Invoke-Go -Arguments @('install', $target)
    if ($null -eq $installResult.ExitCode -or $installResult.ExitCode -ne 0) {
        $code = if ($null -eq $installResult.ExitCode) { 'null' } else { $installResult.ExitCode }
        return @{ Status = '실패'; Detail = "go install $target 종료 코드 $code" }
    }

    return @{ Status = '바꿈'; Detail = '' }
}

Export-ModuleMember -Function Invoke-NvmApp, Invoke-PnpmApp, Invoke-GoApp, Invoke-Nvm, Invoke-Pnpm, Invoke-Go, Get-UserEnv, Set-UserEnv
