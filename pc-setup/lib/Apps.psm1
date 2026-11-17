using module ./Declaration.psm1

Import-Module (Join-Path $PSScriptRoot 'Declaration.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'ItemScript.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'AppWinget.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'AppScoop.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'AppRuntime.psm1') -Force

$script:AppsSchema = @{
    Key      = 'Id'
    Required = @('Id')
    Allowed  = @('Id', 'Origin', 'Scope', 'WingetSource', 'Bucket', 'Elevated', 'NodeLine')
    Enums    = @{
        Origin       = @('winget', 'scoop', 'nvm', 'pnpm', 'go', 'official')
        Scope        = @('machine', 'user')
        WingetSource = @('msstore')
        Bucket       = @('main', 'extras')
    }
    Validate = {
        param($item)
        $problems = [System.Collections.Generic.List[string]]::new()
        $props = $item.PSObject.Properties

        if ($props['Elevated'] -and ($item.Elevated -isnot [bool])) {
            $problems.Add('''Elevated'' 는 $true 또는 $false 다')
        }
        if ($props['NodeLine'] -and ($item.NodeLine -isnot [string] -or [string]::IsNullOrWhiteSpace($item.NodeLine))) {
            $problems.Add('''NodeLine'' 은 버전 줄 문자열이다 (예: ''26'')')
        }

        $origin = if ($props['Origin']) { [string]$item.Origin } else { 'winget' }
        $sourceLabel = $null
        $requiredKeys = @()
        $disallowedKeys = @()

        if ($origin -ceq 'winget') {
            $isMsstore = ($props['WingetSource'] -and [string]$item.WingetSource -ceq 'msstore')
            if ($isMsstore) {
                $sourceLabel = 'winget msstore'
                $disallowedKeys = @('Scope', 'Elevated', 'Bucket', 'NodeLine')
            } else {
                $sourceLabel = 'winget'
                $requiredKeys = @('Scope')
                $disallowedKeys = @('Bucket', 'NodeLine')
            }
        } elseif ($origin -ceq 'scoop') {
            $sourceLabel = 'scoop'
            $requiredKeys = @('Bucket')
            $disallowedKeys = @('Scope', 'WingetSource', 'Elevated', 'NodeLine')
        } elseif ($origin -ceq 'nvm') {
            $sourceLabel = 'nvm'
            $requiredKeys = @('NodeLine')
            $disallowedKeys = @('Scope', 'WingetSource', 'Bucket', 'Elevated')
        } elseif ($origin -ceq 'pnpm' -or $origin -ceq 'go') {
            $sourceLabel = $origin
            $disallowedKeys = @('Scope', 'WingetSource', 'Bucket', 'Elevated', 'NodeLine')
        } elseif ($origin -ceq 'official') {
            $sourceLabel = 'official'
            $disallowedKeys = @('Scope', 'WingetSource', 'Bucket', 'NodeLine')
        }

        if ($null -ne $sourceLabel) {
            foreach ($req in $requiredKeys) {
                if (-not $props[$req]) {
                    $problems.Add("$sourceLabel 항목에는 '$req' 가 있어야 한다")
                }
            }
            foreach ($dis in $disallowedKeys) {
                if ($props[$dis]) {
                    $problems.Add("$sourceLabel 항목에는 '$dis' 를 쓰지 않는다")
                }
            }
        }

        return [string[]]$problems.ToArray()
    }
}

function Get-AppItems {
    # <Root>\apps.psd1 을 읽고 검사해 앱 항목 목록을 돌려준다(Stage = '앱'). 문제가 있으면 DeclarationException.
    param([Parameter(Mandatory)][string]$Root)

    $appsPath = Join-Path $Root 'apps.psd1'
    $items = $null
    $problems = [System.Collections.Generic.List[string]]::new()

    try {
        $items = Read-Declaration -Path $appsPath -Schema $script:AppsSchema
    } catch [DeclarationException] {
        foreach ($p in $_.Exception.Problems) {
            $problems.Add($p)
        }
    }

    if ($null -ne $items) {
        $fileName = Split-Path -Leaf $appsPath
        foreach ($item in $items) {
            $props = $item.PSObject.Properties
            $origin = if ($props['Origin']) { [string]$item.Origin } else { 'winget' }
            if ($origin -ceq 'official') {
                $scriptPath = Join-Path $Root 'apps' "$($item.Id).ps1"
                if (-not (Test-Path -LiteralPath $scriptPath -PathType Leaf)) {
                    $problems.Add("${fileName}:$($item.Line): 스크립트가 없다: apps/$($item.Id).ps1")
                }
            }
        }
    }

    if ($problems.Count -gt 0) {
        throw [DeclarationException]::new([string[]]$problems.ToArray())
    }

    $stageItems = [System.Collections.Generic.List[object]]::new()
    $thisModule = $ExecutionContext.SessionState.Module
    foreach ($item in $items) {
        $props = $item.PSObject.Properties
        $origin = if ($props['Origin']) { [string]$item.Origin } else { 'winget' }

        $elevated = switch ($origin) {
            'winget' {
                $isMsstore = ($props['WingetSource'] -and [string]$item.WingetSource -ceq 'msstore')
                if ($isMsstore) {
                    $false
                } else {
                    ($props['Scope'] -and [string]$item.Scope -ceq 'machine') -or ($props['Elevated'] -and $item.Elevated -eq $true)
                }
            }
            'official' {
                if ($props['Elevated']) { [bool]$item.Elevated } else { $false }
            }
            default { $false }
        }

        if ($origin -ceq 'official') {
            $scriptPath = Join-Path $Root 'apps' "$($item.Id).ps1"
            $invoke = {
                param([bool]$Check)
                & $thisModule {
                    param($p, $c)
                    Invoke-ItemScript -Path $p -Check:$c
                } $scriptPath $Check
            }.GetNewClosure()
        } else {
            $entry = $item
            $invoke = {
                param([bool]$Check)
                & $thisModule {
                    param($orig, $e, $c)
                    switch ($orig) {
                        'winget' { Invoke-WingetApp -Entry $e -Check $c }
                        'scoop'  { Invoke-ScoopApp  -Entry $e -Check $c }
                        'nvm'    { Invoke-NvmApp    -Entry $e -Check $c }
                        'pnpm'   { Invoke-PnpmApp   -Entry $e -Check $c }
                        'go'     { Invoke-GoApp     -Entry $e -Check $c }
                    }
                } $origin $entry $Check
            }.GetNewClosure()
        }

        $stageItems.Add([pscustomobject]@{
            Stage    = '앱'
            Id       = $item.Id
            Elevated = $elevated
            Invoke   = $invoke
        })
    }

    return ,([pscustomobject[]]$stageItems.ToArray())
}

Export-ModuleMember -Function Get-AppItems
