Import-Module (Join-Path $PSScriptRoot 'Report.psm1') -Force

function Invoke-ItemScript {
    # 항목 스크립트를 같은 프로세스에서 부르고 마지막 출력 줄을 결과로 바꾼다 → @{ Status; Detail }
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [switch]$Check
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return @{
            Status = '실패'
            Detail = "스크립트가 없다: $Path"
        }
    }

    trap { continue }

    try {
        $output = if ($Check) {
            & $Path -Check
        } else {
            & $Path
        }
    } catch {
        return @{
            Status = '실패'
            Detail = $_.Exception.Message
        }
    }

    $stringOutputs = @($output | Where-Object { $_ -is [string] -and $_.Trim() -ne '' })
    if ($stringOutputs.Count -eq 0) {
        return @{
            Status = '실패'
            Detail = '결과 줄 없음'
        }
    }

    $lastLine = $stringOutputs[-1].Trim()
    $result = ConvertFrom-ResultText -Text $lastLine -Check:$Check
    if ($null -ne $result) {
        return $result
    }

    return @{
        Status = '실패'
        Detail = "모르는 결과: $lastLine"
    }
}

Export-ModuleMember -Function Invoke-ItemScript
