[CmdletBinding()]
param([switch]$Check)

Import-Module (Join-Path $PSScriptRoot '..' 'lib' 'EnvPath.psm1')

function Get-ClaudeBinDir {
    return (Join-Path $env:USERPROFILE '.local\bin')
}

function Get-ClaudeExePath {
    return (Join-Path (Get-ClaudeBinDir) 'claude.exe')
}

function Test-ExecutableExists {
    param([Parameter(Mandatory)][string]$Path)
    return (Test-Path -LiteralPath $Path -PathType Leaf)
}

function Get-UserPathList {
    return @(Get-UserPathEntries)
}

function Test-ClaudeFirstInUserPath {
    param([Parameter(Mandatory)][string]$BinDir)
    $entries = @(Get-UserPathList)
    if ($entries.Count -eq 0) {
        return $false
    }
    $normalizedTarget = [System.Environment]::ExpandEnvironmentVariables($BinDir).TrimEnd('\')
    return ([System.Environment]::ExpandEnvironmentVariables($entries[0]).TrimEnd('\') -ieq $normalizedTarget)
}

function Invoke-InstallScript {
    param([Parameter(Mandatory)][string]$Uri)
    $proc = Start-Process -FilePath 'pwsh' -ArgumentList @('-NoProfile', '-Command', "irm $Uri | iex") -NoNewWindow -Wait -PassThru
    return $proc.ExitCode
}

function Add-UserPathEntry {
    param([Parameter(Mandatory)][string]$Path)
    return (Add-UserPath -Path $Path -Prepend)
}

function Sync-SessionPath {
    Update-SessionPath
}

function Invoke-Main {
    param([switch]$Check)

    $exePath = Get-ClaudeExePath
    $binDir = Get-ClaudeBinDir
    $exeExists = Test-ExecutableExists -Path $exePath
    $pathOk = Test-ClaudeFirstInUserPath -BinDir $binDir

    if ($exeExists -and $pathOk) {
        Write-Output '그대로'
        return
    }

    if ($Check) {
        $reasons = [System.Collections.Generic.List[string]]::new()
        if (-not $exeExists) { $reasons.Add('claude.exe 없음') }
        if (-not $pathOk) { $reasons.Add('~/.local/bin 이 사용자 PATH 맨 앞이 아님') }
        Write-Output ("다름 ($($reasons -join ', '))")
        return
    }

    $changed = $false
    if (-not $exeExists) {
        $exitCode = Invoke-InstallScript -Uri 'https://claude.ai/install.ps1'
        if ($exitCode -ne 0) {
            Write-Output "실패: 설치 스크립트 종료 코드 $exitCode"
            return
        }
        if (-not (Test-ExecutableExists -Path $exePath)) {
            Write-Output '실패: claude.exe 가 생기지 않았다'
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
