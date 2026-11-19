[CmdletBinding()]
param([switch]$Check)

function Get-DisplayDrivers {
    return @(Get-CimInstance -ClassName Win32_PnPSignedDriver -Filter "DeviceClass='DISPLAY'")
}

function Invoke-Main {
    param([switch]$Check)

    $drivers = @(Get-DisplayDrivers)
    $nvidiaDevices = @($drivers | Where-Object {
        $null -ne $_.HardWareID -and $_.HardWareID -like 'PCI\VEN_10DE*'
    })

    if ($nvidiaDevices.Count -eq 0) {
        Write-Output '그대로'
        return
    }

    foreach ($dev in $nvidiaDevices) {
        if ($dev.DriverProviderName -ine 'NVIDIA') {
            Write-Output '할 일: NVIDIA 드라이버 설치'
            return
        }
    }

    Write-Output '그대로'
}

if ($MyInvocation.InvocationName -ne '.') {
    Invoke-Main -Check:$Check
}
