[CmdletBinding()]
param([switch]$Check)

Import-Module (Join-Path $PSScriptRoot '..' 'lib' 'EnvPath.psm1')

function Get-FlutterDir {
    return (Join-Path $env:USERPROFILE 'develop\flutter')
}

function Get-FlutterBinDir {
    return (Join-Path (Get-FlutterDir) 'bin')
}

function Get-FlutterBatPath {
    return (Join-Path (Get-FlutterBinDir) 'flutter.bat')
}

function Test-FlutterBatExists {
    param([Parameter(Mandatory)][string]$Path)
    return (Test-Path -LiteralPath $Path -PathType Leaf)
}

function Test-FlutterDirExists {
    param([Parameter(Mandatory)][string]$Path)
    return (Test-Path -LiteralPath $Path -PathType Container)
}

function Ensure-Directory {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function Get-UserPathList {
    return @(Get-UserPathEntries)
}

function Test-FlutterInUserPath {
    param([Parameter(Mandatory)][string]$BinDir)
    $normalizedTarget = [System.Environment]::ExpandEnvironmentVariables($BinDir).TrimEnd('\')
    foreach ($entry in @(Get-UserPathList)) {
        if ([System.Environment]::ExpandEnvironmentVariables($entry).TrimEnd('\') -ieq $normalizedTarget) {
            return $true
        }
    }
    return $false
}

function Test-GitAvailable {
    return ($null -ne (Get-Command -Name 'git' -ErrorAction SilentlyContinue))
}

function Invoke-GitClone {
    param([Parameter(Mandatory)][string[]]$Arguments)
    & git @Arguments | Out-Host
    return $LASTEXITCODE
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

    $flutterDir = Get-FlutterDir
    $binDir = Get-FlutterBinDir
    $batPath = Get-FlutterBatPath
    $batExists = Test-FlutterBatExists -Path $batPath
    $pathOk = Test-FlutterInUserPath -BinDir $binDir

    if ($batExists -and $pathOk) {
        Write-Output '그대로'
        return
    }

    if ($Check) {
        $reasons = [System.Collections.Generic.List[string]]::new()
        if (-not $batExists) { $reasons.Add('flutter.bat 없음') }
        if (-not $pathOk) { $reasons.Add('flutter\bin 이 사용자 PATH 에 없음') }
        Write-Output ("다름 ($($reasons -join ', '))")
        return
    }

    Sync-SessionPath

    $changed = $false
    if (-not $batExists) {
        if (-not (Test-FlutterDirExists -Path $flutterDir)) {
            if (-not (Test-GitAvailable)) {
                Write-Output '실패: git 없음'
                return
            }
            $parentDir = Split-Path -Path $flutterDir -Parent
            Ensure-Directory -Path $parentDir
            $exitCode = Invoke-GitClone -Arguments @('clone', '-b', 'stable', 'https://github.com/flutter/flutter.git', $flutterDir)
            if ($exitCode -ne 0) {
                Write-Output "실패: git clone 종료 코드 $exitCode"
                return
            }
            $changed = $true
        } else {
            Write-Output '실패: ~/develop/flutter 가 Flutter 저장소가 아니다'
            return
        }
    }

    if (-not $pathOk) {
        if (Add-UserPathEntry -Path $binDir) {
            Sync-SessionPath
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
