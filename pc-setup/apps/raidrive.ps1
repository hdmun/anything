[CmdletBinding()]
param([switch]$Check)

function Get-RaiDriveUninstallEntry {
    $paths = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    foreach ($p in $paths) {
        $match = Get-ItemProperty -Path $p -ErrorAction SilentlyContinue |
            Where-Object { $_.DisplayName -and $_.DisplayName.StartsWith('RaiDrive') } |
            Select-Object -First 1
        if ($null -ne $match) {
            return $match
        }
    }
    return $null
}

function Get-RaiDriveDownloadPage {
    $resp = Invoke-WebRequest -Uri 'https://www.raidrive.com/download' -UseBasicParsing
    return [string]$resp.Content
}

function Invoke-FileDownload {
    param(
        [Parameter(Mandatory)][string]$Uri,
        [Parameter(Mandatory)][string]$OutFile
    )
    Invoke-WebRequest -Uri $Uri -OutFile $OutFile -UseBasicParsing
}

function Invoke-MsiExec {
    param([Parameter(Mandatory)][string[]]$Arguments)
    $quotedArgs = @(foreach ($arg in $Arguments) {
        if ($arg -match '\s' -and -not ($arg.StartsWith('"') -and $arg.EndsWith('"'))) {
            "`"$arg`""
        } else {
            $arg
        }
    })
    $proc = Start-Process -FilePath 'msiexec.exe' -ArgumentList $quotedArgs -NoNewWindow -Wait -PassThru
    return $proc.ExitCode
}

function Invoke-Main {
    param([switch]$Check)

    if ($null -ne (Get-RaiDriveUninstallEntry)) {
        Write-Output '그대로'
        return
    }

    if ($Check) {
        Write-Output '다름 (설치 안 됨)'
        return
    }

    $html = Get-RaiDriveDownloadPage
    $pattern = 'https://app\.raidrive\.com/download/raidrive\.mount/release/RaiDrive\.Mount_[0-9.]+_x64\.msi'
    $match = [regex]::Match($html, $pattern)
    if (-not $match.Success) {
        Write-Output '실패: RaiDrive 내려받기 주소를 찾지 못했다'
        return
    }

    $msiUrl = $match.Value
    $tempDir = Join-Path $env:TEMP ("raidrive-" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
    try {
        $fileName = Split-Path -Leaf $msiUrl
        $msiPath = Join-Path $tempDir $fileName

        Write-Host "RaiDrive 내려받기 중: $msiUrl"
        Invoke-FileDownload -Uri $msiUrl -OutFile $msiPath

        Write-Host "RaiDrive 설치 중: $fileName"
        $exitCode = Invoke-MsiExec -Arguments @('/i', $msiPath, '/qn', '/norestart')

        if ($exitCode -eq 0) {
            if ($null -ne (Get-RaiDriveUninstallEntry)) {
                Write-Output '바꿈'
                return
            }
            Write-Output '실패: msiexec 종료 코드 0 후에도 설치되지 않았다'
            return
        }

        if ($exitCode -eq 3010) {
            Write-Output '할 일: 재부팅 후 셋업 다시 실행'
            return
        }

        Write-Output "실패: msiexec 종료 코드 $exitCode"
    } finally {
        if (Test-Path -LiteralPath $tempDir) {
            Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    Invoke-Main -Check:$Check
}
