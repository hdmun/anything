[CmdletBinding()]
param([switch]$Check)

Import-Module (Join-Path $PSScriptRoot '..' 'lib' 'EnvPath.psm1')

function Get-AgyBinDir {
    return (Join-Path $env:LOCALAPPDATA 'agy\bin')
}

function Get-AgyExePath {
    return (Join-Path (Get-AgyBinDir) 'agy.exe')
}

function Test-ExecutableExists {
    param([Parameter(Mandatory)][string]$Path)
    return (Test-Path -LiteralPath $Path -PathType Leaf)
}

function Get-UserPathList {
    return @(Get-UserPathEntries)
}

function Test-AgyInUserPath {
    param([Parameter(Mandatory)][string]$BinDir)
    $normalizedTarget = [System.Environment]::ExpandEnvironmentVariables($BinDir).TrimEnd('\')
    foreach ($entry in @(Get-UserPathList)) {
        if ([System.Environment]::ExpandEnvironmentVariables($entry).TrimEnd('\') -ieq $normalizedTarget) {
            return $true
        }
    }
    return $false
}

function Invoke-InstallScript {
    param([Parameter(Mandatory)][string]$Uri)
    $proc = Start-Process -FilePath 'pwsh' -ArgumentList @('-NoProfile', '-Command', "irm $Uri | iex") -NoNewWindow -Wait -PassThru
    return $proc.ExitCode
}

function Add-UserPathEntry {
    param([Parameter(Mandatory)][string]$Path)
    return (Add-UserPath -Path $Path)
}

function Sync-SessionPath {
    Update-SessionPath
}

function Invoke-Main {
    param([switch]$Check)

    $exePath = Get-AgyExePath
    $binDir = Get-AgyBinDir
    $exeExists = Test-ExecutableExists -Path $exePath
    $pathOk = Test-AgyInUserPath -BinDir $binDir

    if ($exeExists -and $pathOk) {
        Write-Output '그대로'
        return
    }

    if ($Check) {
        $reasons = [System.Collections.Generic.List[string]]::new()
        if (-not $exeExists) { $reasons.Add('agy.exe 없음') }
        if (-not $pathOk) { $reasons.Add('agy\bin 이 사용자 PATH 에 없음') }
        Write-Output ("다름 ($($reasons -join ', '))")
        return
    }

    $changed = $false
    if (-not $exeExists) {
        $exitCode = Invoke-InstallScript -Uri 'https://antigravity.google/cli/install.ps1'
        if ($exitCode -ne 0) {
            Write-Output "실패: 설치 스크립트 종료 코드 $exitCode"
            return
        }
        if (-not (Test-ExecutableExists -Path $exePath)) {
            Write-Output '실패: agy.exe 가 생기지 않았다'
            return
        }
        Sync-SessionPath
        $changed = $true
    }

    if (-not $pathOk) {
        if (Add-UserPathEntry -Path $binDir) {
            $changed = $true
        }
    }

    if ($changed) {
        Write-Output '바꿈'
    } else {
        Write-Output '그대로'
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    Invoke-Main -Check:$Check
}
