using module ./Declaration.psm1

Import-Module (Join-Path $PSScriptRoot 'Declaration.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'ItemScript.psm1') -Force

$script:RepoToolsSchema = @{
    Key      = 'Id'
    Required = @('Id')
    Allowed  = @('Id', 'Elevated')
    Validate = {
        param($item)
        $problems = [System.Collections.Generic.List[string]]::new()
        $props = $item.PSObject.Properties

        if ($props['Elevated'] -and ($item.Elevated -isnot [bool])) {
            $problems.Add('Elevated 값은 $true/$false 여야 한다')
        }

        if ($props['Id']) {
            $idVal = [string]$item.Id
            $segments = $idVal -split '[/\\]'
            if ([System.IO.Path]::IsPathRooted($idVal) -or ($segments -contains '..')) {
                $problems.Add('Id 는 저장소 루트 기준 폴더 이름이다')
            }
        }

        return [string[]]$problems.ToArray()
    }
}

function Get-RepoToolItems {
    # <Root>\repo-tools.psd1 을 읽고 검사해 항목 목록을 돌려준다.
    # 항목: Stage = '저장소 도구', Id = 선언의 Id, Elevated = [bool]$item.Elevated,
    #       Invoke = { param($Check) Invoke-ItemScript -Path <저장소>\<Id>\install.ps1 -Check:$Check }
    # <저장소> = Split-Path $Root -Parent. 문제가 있으면 DeclarationException.
    param([Parameter(Mandatory)][string]$Root)

    $resolvedRoot = [System.IO.Path]::GetFullPath($ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Root))
    $repoToolsPath = Join-Path $resolvedRoot 'repo-tools.psd1'
    $repoRoot = Split-Path -Path $resolvedRoot -Parent
    $items = $null
    $problems = [System.Collections.Generic.List[string]]::new()

    try {
        $items = Read-Declaration -Path $repoToolsPath -Schema $script:RepoToolsSchema
    } catch [DeclarationException] {
        foreach ($p in $_.Exception.Problems) {
            $problems.Add($p)
        }
    }

    if ($null -ne $items) {
        $fileName = Split-Path -Leaf $repoToolsPath
        foreach ($item in $items) {
            $installPath = Join-Path $repoRoot $item.Id 'install.ps1'
            if (-not (Test-Path -LiteralPath $installPath -PathType Leaf)) {
                $problems.Add("${fileName}:$($item.Line): install.ps1 이 없다: $($item.Id)/install.ps1")
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
        $elevated = [bool]($props['Elevated'] -and $item.Elevated -eq $true)
        $installPath = Join-Path $repoRoot $item.Id 'install.ps1'

        $invoke = {
            param([bool]$Check)
            & $thisModule {
                param($p, $c)
                Invoke-ItemScript -Path $p -Check:$c
            } $installPath $Check
        }.GetNewClosure()

        $stageItems.Add([pscustomobject]@{
            Stage    = '저장소 도구'
            Id       = [string]$item.Id
            Elevated = $elevated
            Invoke   = $invoke
        })
    }

    return ,([pscustomobject[]]$stageItems.ToArray())
}

Export-ModuleMember -Function Get-RepoToolItems
