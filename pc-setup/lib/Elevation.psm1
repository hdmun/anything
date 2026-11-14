Import-Module (Join-Path $PSScriptRoot 'Report.psm1') -Force

function Test-AdminWindow {
    # 현재 프로세스가 관리자 토큰으로 돌고 있으면 $true (UAC 로 제한된 관리자 계정의 일반 창은 $false)
    $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [System.Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Invoke-ElevatedPhase {
    # setup.ps1 을 승격해 '-Phase Elevated -ResultPath <임시 JSON>' 으로 띄우고 끝날 때까지 기다린다.
    # → @{ Requested = <UAC 요청 횟수 0|1>; Results = <결과 객체 배열>; Error = <'' | '승격 거부됨' | '승격 단계 결과 없음'> }
    param(
        [Parameter(Mandatory)][string]$SetupScript,
        [string[]]$Skip = @()
    )

    $guid = [System.Guid]::NewGuid().ToString()
    $tempFile = Join-Path $env:TEMP "pc-setup-elevated-$guid.json"

    $argsList = "-NoProfile -File `"$SetupScript`" -Phase Elevated -ResultPath `"$tempFile`""
    $skipItems = @(
        foreach ($s in $Skip) {
            foreach ($part in ($s -split ',')) {
                $t = $part.Trim()
                if ($t -ne '') { $t }
            }
        }
    )
    if ($skipItems.Count -gt 0) {
        $skipStr = $skipItems -join ','
        $argsList += " -Skip `"$skipStr`""
    }

    $processPath = (Get-Process -Id $PID).Path

    $requested = 1
    $results = @()
    $error = ''

    try {
        try {
            Start-Process -FilePath $processPath -Verb RunAs -Wait -ArgumentList $argsList
        } catch {
            return @{
                Requested = 1
                Results   = @()
                Error     = '승격 거부됨'
            }
        }

        if (-not (Test-Path -LiteralPath $tempFile -PathType Leaf)) {
            $error = '승격 단계 결과 없음'
        } else {
            $content = Get-Content -LiteralPath $tempFile -Raw -Encoding utf8
            if ([string]::IsNullOrWhiteSpace($content)) {
                $error = '승격 단계 결과 없음'
            } else {
                try {
                    $json = $content | ConvertFrom-Json
                    if ($null -eq $json -or $null -eq $json.Results) {
                        $error = '승격 단계 결과 없음'
                    } else {
                        $parsedResults = [System.Collections.Generic.List[object]]::new()
                        foreach ($r in @($json.Results)) {
                            $parsedResults.Add((New-SetupResult -Stage $r.Stage -Id $r.Id -Status $r.Status -Detail ($r.Detail ?? '')))
                        }
                        $results = [object[]]$parsedResults.ToArray()
                    }
                } catch {
                    $error = '승격 단계 결과 없음'
                }
            }
        }

        return @{
            Requested = $requested
            Results   = $results
            Error     = $error
        }
    } finally {
        if (Test-Path -LiteralPath $tempFile) {
            Remove-Item -LiteralPath $tempFile -Force -ErrorAction SilentlyContinue
        }
    }
}

Export-ModuleMember -Function Test-AdminWindow, Invoke-ElevatedPhase
