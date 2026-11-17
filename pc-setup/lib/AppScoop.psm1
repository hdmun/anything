Import-Module (Join-Path $PSScriptRoot 'EnvPath.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'Elevation.psm1') -Force

function Get-ScoopBucketNames {
    param([object[]]$Output)

    $names = [System.Collections.Generic.List[string]]::new()
    if ($null -eq $Output) {
        return [string[]]@()
    }

    foreach ($item in $Output) {
        if ($null -eq $item) {
            continue
        }
        $name = $null
        if ($item -is [System.Collections.IDictionary]) {
            if ($item.Contains('Name')) {
                $name = $item['Name']
            }
        } else {
            $prop = $item.PSObject.Properties['Name']
            if ($null -ne $prop) {
                $name = $prop.Value
            }
        }
        if ($null -ne $name -and -not [string]::IsNullOrWhiteSpace([string]$name)) {
            $names.Add([string]$name)
        }
    }

    return [string[]]$names.ToArray()
}

function Invoke-Scoop {
    # scoop 을 부르고 → @{ ExitCode = <int>; Output = <object[]> }. scoop 이 없으면 ExitCode = $null.
    param([Parameter(Mandatory)][string[]]$Arguments)

    $cmd = Get-Command scoop -ErrorAction SilentlyContinue
    if ($null -eq $cmd) {
        return @{ ExitCode = $null; Output = [object[]]@() }
    }

    $rawOutput = & $cmd.Source @Arguments 2>&1
    $exitCode = $LASTEXITCODE
    $items = if ($null -eq $rawOutput) {
        [object[]]@()
    } else {
        [object[]]@($rawOutput)
    }

    return @{ ExitCode = [int]$exitCode; Output = $items }
}

function Install-Scoop {
    # 공식 설치 스크립트(https://get.scoop.sh)를 일반 권한으로 실행한다. 성공하면 $true.
    if (Test-AdminWindow) {
        return $false
    }

    $prevErrorAction = $ErrorActionPreference
    $ErrorActionPreference = 'Stop'
    try {
        $script = Invoke-RestMethod -Uri 'https://get.scoop.sh'
        if ([string]::IsNullOrWhiteSpace($script)) {
            return $false
        }
        Invoke-Expression $script
        return $true
    } catch {
        return $false
    } finally {
        $ErrorActionPreference = $prevErrorAction
    }
}

function Invoke-ScoopApp {
    # → @{ Status; Detail }
    param([Parameter(Mandatory)]$Entry, [bool]$Check)

    $id = [string]$Entry.Id
    $bucket = [string]$Entry.Bucket
    $changed = $false

    $versionResult = Invoke-Scoop -Arguments @('--version')
    if ($null -eq $versionResult.ExitCode) {
        if ($Check) {
            return @{ Status = '다름'; Detail = 'scoop 없음' }
        }
        if (-not (Install-Scoop)) {
            return @{ Status = '실패'; Detail = 'scoop 설치 실패' }
        }
        Update-SessionPath
        $changed = $true
    }

    $bucketResult = Invoke-Scoop -Arguments @('bucket', 'list')
    if ($null -eq $bucketResult.ExitCode) {
        return @{ Status = '실패'; Detail = 'scoop 이 없다' }
    }
    if ($bucketResult.ExitCode -ne 0) {
        return @{ Status = '실패'; Detail = "scoop bucket list 종료 코드 $($bucketResult.ExitCode)" }
    }

    $bucketNames = Get-ScoopBucketNames -Output $bucketResult.Output
    if ($bucketNames -notcontains $bucket) {
        if ($Check) {
            return @{ Status = '다름'; Detail = "버킷 $bucket 없음" }
        }
        $addResult = Invoke-Scoop -Arguments @('bucket', 'add', $bucket)
        if ($null -eq $addResult.ExitCode -or $addResult.ExitCode -ne 0) {
            $addCode = if ($null -eq $addResult.ExitCode) { 'null' } else { $addResult.ExitCode }
            return @{ Status = '실패'; Detail = "scoop bucket add $bucket 종료 코드 $addCode" }
        }
        $changed = $true
    }

    $prefixResult = Invoke-Scoop -Arguments @('prefix', $id)
    if ($null -ne $prefixResult.ExitCode -and $prefixResult.ExitCode -eq 0) {
        if ($changed) {
            return @{ Status = '바꿈'; Detail = '' }
        }
        return @{ Status = '그대로'; Detail = '' }
    }

    if ($Check) {
        return @{ Status = '다름'; Detail = '설치 안 됨' }
    }

    $installTarget = "$bucket/$id"
    $installResult = Invoke-Scoop -Arguments @('install', $installTarget)
    if ($null -ne $installResult.ExitCode -and $installResult.ExitCode -eq 0) {
        Update-SessionPath
        return @{ Status = '바꿈'; Detail = '' }
    }

    $installCode = if ($null -eq $installResult.ExitCode) { 'null' } else { $installResult.ExitCode }
    return @{ Status = '실패'; Detail = "scoop install $installTarget 종료 코드 $installCode" }
}

Export-ModuleMember -Function Invoke-ScoopApp, Invoke-Scoop, Install-Scoop
