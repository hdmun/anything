function Invoke-NvmApp {
    param([Parameter(Mandatory)]$Entry, [bool]$Check)
    throw '아직 구현되지 않은 원천: nvm'
}

function Invoke-PnpmApp {
    param([Parameter(Mandatory)]$Entry, [bool]$Check)
    throw '아직 구현되지 않은 원천: pnpm'
}

function Invoke-GoApp {
    param([Parameter(Mandatory)]$Entry, [bool]$Check)
    throw '아직 구현되지 않은 원천: go'
}

Export-ModuleMember -Function Invoke-NvmApp, Invoke-PnpmApp, Invoke-GoApp
