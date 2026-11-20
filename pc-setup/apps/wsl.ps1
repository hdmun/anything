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

function Invoke-Wsl {
    param([Parameter(Mandatory)][string[]]$Arguments)
    $proc = Start-Process -FilePath 'wsl.exe' -ArgumentList $Arguments -NoNewWindow -Wait -PassThru
    return $proc.ExitCode
}

function Invoke-Main {
    param([switch]$Check)

    $pkg = Get-WslPackage
    $featureState = Get-FeatureState -Name 'VirtualMachinePlatform'

    $hasPkg = ($null -ne $pkg)
    $hasFeature = ($featureState -eq 1)

    if ($hasPkg -and $hasFeature) {
        Write-Output '그대로'
        return
    }

    if ($Check) {
        $missing = [System.Collections.Generic.List[string]]::new()
        if (-not $hasPkg) {
            $missing.Add('WSL 패키지 없음')
        }
        if (-not $hasFeature) {
            $missing.Add('VirtualMachinePlatform 꺼짐')
        }
        Write-Output ("다름 ({0})" -f ($missing -join ', '))
        return
    }

    if ($hasPkg -and -not $hasFeature) {
        Write-Output '할 일: 재부팅 후 셋업 다시 실행'
        return
    }

    if (-not (Test-WslCommand)) {
        Write-Output '실패: wsl.exe 없음'
        return
    }

    Write-Host 'WSL 설치 중: wsl --install --no-distribution'
    $exitCode = Invoke-Wsl -Arguments @('--install', '--no-distribution')

    $pkgAfter = Get-WslPackage
    $featureAfter = Get-FeatureState -Name 'VirtualMachinePlatform'

    if ($null -ne $pkgAfter -and $featureAfter -eq 1) {
        Write-Output '바꿈'
        return
    }

    if ($null -ne $pkgAfter) {
        Write-Output '할 일: 재부팅 후 셋업 다시 실행'
        return
    }

    if ($exitCode -ne 0) {
        Write-Output "실패: wsl --install --no-distribution 종료 코드 $exitCode"
        return
    }

    Write-Output '실패: wsl --install --no-distribution 후에도 WSL 패키지가 없다'
}

if ($MyInvocation.InvocationName -ne '.') {
    Invoke-Main -Check:$Check
}
