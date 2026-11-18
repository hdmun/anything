Import-Module (Join-Path $PSScriptRoot 'EnvPath.psm1') -Force

function Format-WingetExitCode {
    param([Parameter(Mandatory)][long]$ExitCode)
    return ('0x{0:X8}' -f ($ExitCode -band 0xFFFFFFFFL))
}

function Get-LastNonEmptyLine {
    param([string[]]$Lines)

    if ($null -eq $Lines) {
        return $null
    }
    for ($i = $Lines.Count - 1; $i -ge 0; $i--) {
        $line = $Lines[$i]
        if (-not [string]::IsNullOrWhiteSpace($line)) {
            return $line.Trim()
        }
    }
    return $null
}

function Invoke-Winget {
    # winget 을 부르고 → @{ ExitCode = <int>; Output = <string[]> }. winget 이 없으면 ExitCode = $null.
    # 테스트는 이 함수를 Mock 한다(-ModuleName AppWinget).
    param([Parameter(Mandatory)][string[]]$Arguments)

    $cmd = Get-Command winget -ErrorAction SilentlyContinue
    if ($null -eq $cmd) {
        return @{ ExitCode = $null; Output = [string[]]@() }
    }

    $rawOutput = & $cmd.Source @Arguments 2>&1
    $exitCode = $LASTEXITCODE
    $lines = [System.Collections.Generic.List[string]]::new()
    if ($null -ne $rawOutput) {
        foreach ($item in @($rawOutput)) {
            $lines.Add($item.ToString())
        }
    }

    return @{ ExitCode = [int]$exitCode; Output = [string[]]$lines.ToArray() }
}

function Invoke-WingetApp {
    # → @{ Status; Detail }
    param([Parameter(Mandatory)]$Entry, [bool]$Check)

    $wingetSource = if ($Entry -is [System.Collections.IDictionary]) {
        $Entry['WingetSource']
    } else {
        $prop = $Entry.PSObject.Properties['WingetSource']
        if ($null -ne $prop) { $prop.Value } else { $null }
    }
    $isMsstore = ($null -ne $wingetSource -and [string]$wingetSource -ceq 'msstore')
    $source = if ($isMsstore) { 'msstore' } else { 'winget' }
    $id = [string]$Entry.Id

    $listArgs = @(
        'list', '--id', $id, '-e',
        '--accept-source-agreements', '--disable-interactivity',
        '--source', $source
    )
    $listResult = Invoke-Winget -Arguments $listArgs
    if ($null -eq $listResult.ExitCode) {
        return @{ Status = '실패'; Detail = 'winget 이 없다' }
    }

    $listCode = ([long]$listResult.ExitCode) -band 0xFFFFFFFFL
    if ($listCode -eq 0L) {
        return @{ Status = '그대로'; Detail = '' }
    }
    if ($listCode -ne 0x8A150014L) {
        $hex = Format-WingetExitCode -ExitCode $listCode
        return @{ Status = '실패'; Detail = "winget list 종료 코드 $hex" }
    }

    if ($Check) {
        return @{ Status = '다름'; Detail = '설치 안 됨' }
    }

    $installArgs = [System.Collections.Generic.List[string]]@(
        'install', '--id', $id, '-e',
        '--no-upgrade', '--silent',
        '--accept-package-agreements', '--accept-source-agreements', '--disable-interactivity',
        '--source', $source
    )
    if (-not $isMsstore) {
        $installArgs.Add('--scope')
        $installArgs.Add([string]$Entry.Scope)
    }

    $installResult = Invoke-Winget -Arguments ([string[]]$installArgs.ToArray())
    if ($null -eq $installResult.ExitCode) {
        return @{ Status = '실패'; Detail = 'winget 이 없다' }
    }

    $installCode = ([long]$installResult.ExitCode) -band 0xFFFFFFFFL
    if ($installCode -eq 0L) {
        Update-SessionPath
        return @{ Status = '바꿈'; Detail = '' }
    }
    if ($installCode -eq 0x8A150109L) {
        Update-SessionPath
        return @{ Status = '할 일'; Detail = '재부팅 후 셋업 다시 실행' }
    }

    $hex = Format-WingetExitCode -ExitCode $installCode
    $detail = "winget install 종료 코드 $hex"
    $lastLine = Get-LastNonEmptyLine -Lines $installResult.Output
    if ($null -ne $lastLine) {
        $detail = "$detail ($lastLine)"
    }
    return @{ Status = '실패'; Detail = $detail }
}

Export-ModuleMember -Function Invoke-WingetApp, Invoke-Winget
