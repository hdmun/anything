[CmdletBinding()]
param([switch]$Check)

function Get-WslPackage {
    Get-AppxPackage -Name 'MicrosoftCorporationII.WindowsSubsystemForLinux' -ErrorAction SilentlyContinue
}

function Get-FeatureState {
    param([Parameter(Mandatory)][string]$Name)
    $feature = Get-CimInstance -ClassName 'Win32_OptionalFeature' -Filter "Name = '$Name'" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -eq $feature) {
        return $null
    }
    return $feature.InstallState
}

function Test-WslCommand {
    return ($null -ne (Get-Command -Name 'wsl.exe' -ErrorAction SilentlyContinue))
}

function Invoke-WslListRaw {
    $prev = $env:WSL_UTF8
    $env:WSL_UTF8 = '1'
    try {
        $output = & wsl.exe -l -q 2>&1
        return ($output -join "`n")
    } finally {
        if ($null -eq $prev) {
            Remove-Item Env:WSL_UTF8 -ErrorAction SilentlyContinue
        } else {
            $env:WSL_UTF8 = $prev
        }
    }
}

function Get-WslDistros {
    $raw = Invoke-WslListRaw
    if ([string]::IsNullOrEmpty($raw)) {
        return @()
    }
    $cleaned = $raw -replace "`0", ''
    $lines = $cleaned -split "`r?`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }
    return @($lines)
}

function Invoke-Wsl {
    param([Parameter(Mandatory)][string[]]$Arguments)
    $proc = Start-Process -FilePath 'wsl.exe' -ArgumentList $Arguments -NoNewWindow -Wait -PassThru
    return $proc.ExitCode
}

function Invoke-Main {
    param([switch]$Check)

    $pkg = Get-WslPackage
    $featureState = Get-FeatureState -Name 'VirtualMachinePlatform'

    if ($null -eq $pkg -or $featureState -ne 1) {
        Write-Output '할 일: 재부팅 후 셋업 다시 실행'
        return
    }

    if (-not (Test-WslCommand)) {
        Write-Output '실패: wsl.exe 없음'
        return
    }

    $distros = @(Get-WslDistros)
    if ($distros | Where-Object { $_ -ceq 'Ubuntu-24.04' }) {
        Write-Output '그대로'
        return
    }

    if ($Check) {
        Write-Output '다름 (배포판 없음)'
        return
    }

    Write-Host 'Ubuntu-24.04 설치 중: wsl --install -d Ubuntu-24.04 --no-launch'
    $exitCode = Invoke-Wsl -Arguments @('--install', '-d', 'Ubuntu-24.04', '--no-launch')

    $distrosAfter = @(Get-WslDistros)
    if ($distrosAfter | Where-Object { $_ -ceq 'Ubuntu-24.04' }) {
        Write-Output '할 일: wsl -d Ubuntu-24.04 로 처음 실행해 사용자를 만든다'
        return
    }

    if ($exitCode -ne 0) {
        Write-Output "실패: wsl --install -d Ubuntu-24.04 --no-launch 종료 코드 $exitCode"
        return
    }

    Write-Output '실패: wsl --install -d Ubuntu-24.04 --no-launch 후에도 배포판이 없다'
}

if ($MyInvocation.InvocationName -ne '.') {
    Invoke-Main -Check:$Check
}
