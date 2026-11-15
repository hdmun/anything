Import-Module (Join-Path $PSScriptRoot '..' 'lib' 'Setup.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'SandboxJudge.psm1') -Force

function Invoke-Wsb {
    # wsb 를 부르고 표준 출력 문자열을 돌려준다. 종료 코드가 0 이 아니면 예외.
    param([string[]]$Arguments)

    $prevEap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = & wsb @Arguments 2>&1
        $exitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $prevEap
    }

    $text = if ($null -eq $output) {
        ''
    } else {
        (@($output) | ForEach-Object { $_.ToString() }) -join "`n"
    }

    if ($exitCode -ne 0) {
        throw "wsb 실행 실패 (종료 코드 $exitCode): $text"
    }

    return $text
}

function Get-RunningSandboxIds {
    # wsb list --raw → id 문자열 배열
    $raw = Invoke-Wsb -Arguments @('list', '--raw')
    if ([string]::IsNullOrWhiteSpace($raw)) {
        return ,([string[]]@())
    }

    $parsed = $raw | ConvertFrom-Json
    $ids = [System.Collections.Generic.List[string]]::new()
    if ($null -ne $parsed -and $null -ne $parsed.WindowsSandboxEnvironments) {
        foreach ($envItem in $parsed.WindowsSandboxEnvironments) {
            if ($null -ne $envItem -and -not [string]::IsNullOrWhiteSpace([string]$envItem.Id)) {
                $ids.Add([string]$envItem.Id)
            }
        }
    }

    return ,([string[]]$ids.ToArray())
}

function Export-HeadFiles {
    # <InDir>\repo.bundle, <InDir>\bootstrap.ps1, <InDir>\sandbox-guest.ps1 (HEAD 의 바이트 그대로)
    param(
        [string]$RepoRoot,
        [string]$InDir
    )

    $resolvedRepo = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($RepoRoot)
    if (-not (Test-Path -LiteralPath $InDir -PathType Container)) {
        New-Item -Path $InDir -ItemType Directory -Force | Out-Null
    }
    $resolvedInDir = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($InDir)
    $bundlePath = Join-Path $resolvedInDir 'repo.bundle'

    $prevEap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $bundleOut = & git -C $resolvedRepo bundle create $bundlePath HEAD 2>&1
        $bundleExit = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $prevEap
    }
    if ($bundleExit -ne 0) {
        throw "git bundle create 실패 (종료 코드 $bundleExit): $($bundleOut -join "`n")"
    }

    $tmpZip = Join-Path ([System.IO.Path]::GetTempPath()) ("pc-setup-head-" + [System.Guid]::NewGuid().ToString() + '.zip')
    try {
        $prevEap = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try {
            $archiveOut = & git -C $resolvedRepo archive --format=zip -o $tmpZip HEAD pc-setup/bootstrap.ps1 pc-setup/test/sandbox-guest.ps1 2>&1
            $archiveExit = $LASTEXITCODE
        } finally {
            $ErrorActionPreference = $prevEap
        }
        if ($archiveExit -ne 0) {
            throw "git archive 실패 (종료 코드 $archiveExit): $($archiveOut -join "`n")"
        }

        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $wanted = @{
            'pc-setup/bootstrap.ps1'          = (Join-Path $resolvedInDir 'bootstrap.ps1')
            'pc-setup/test/sandbox-guest.ps1' = (Join-Path $resolvedInDir 'sandbox-guest.ps1')
        }
        $found = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

        $zip = [System.IO.Compression.ZipFile]::OpenRead($tmpZip)
        try {
            foreach ($entry in $zip.Entries) {
                $entryName = $entry.FullName.Replace('\', '/')
                if ($wanted.ContainsKey($entryName)) {
                    $destPath = $wanted[$entryName]
                    $inStream = $entry.Open()
                    try {
                        $outStream = [System.IO.File]::Create($destPath)
                        try {
                            $inStream.CopyTo($outStream)
                        } finally {
                            $outStream.Dispose()
                        }
                    } finally {
                        $inStream.Dispose()
                    }
                    $null = $found.Add($entryName)
                }
            }
        } finally {
            $zip.Dispose()
        }

        foreach ($req in $wanted.Keys) {
            if (-not $found.Contains($req)) {
                throw "HEAD 아카이브에 파일이 없다: $req"
            }
        }
    } finally {
        if (Test-Path -LiteralPath $tmpZip -PathType Leaf) {
            Remove-Item -LiteralPath $tmpZip -Force -ErrorAction SilentlyContinue
        }
    }
}

function New-WsbConfig {
    # → .wsb XML 문자열
    param(
        [string]$InDir,
        [string]$OutDir
    )

    $escapedIn = [System.Security.SecurityElement]::Escape($InDir)
    $escapedOut = [System.Security.SecurityElement]::Escape($OutDir)

    return @"
<Configuration>
  <MappedFolders>
    <MappedFolder><HostFolder>$escapedIn</HostFolder><SandboxFolder>C:\pcs\in</SandboxFolder><ReadOnly>true</ReadOnly></MappedFolder>
    <MappedFolder><HostFolder>$escapedOut</HostFolder><SandboxFolder>C:\pcs\out</SandboxFolder><ReadOnly>false</ReadOnly></MappedFolder>
  </MappedFolders>
  <LogonCommand><Command>powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\pcs\in\sandbox-guest.ps1</Command></LogonCommand>
  <MemoryInMB>8192</MemoryInMB>
</Configuration>
"@
}

function Start-TestSandbox {
    # → 새 Sandbox id
    param([string]$Config)

    $raw = Invoke-Wsb -Arguments @('start', '--config', $Config, '--raw')
    if (-not [string]::IsNullOrWhiteSpace($raw)) {
        try {
            $parsed = $raw | ConvertFrom-Json -ErrorAction Stop
            if ($null -ne $parsed -and -not [string]::IsNullOrWhiteSpace([string]$parsed.Id)) {
                return [string]$parsed.Id
            }
        } catch {
            # JSON 이 아니면 실행 중 목록 조회로 fallback 한다
        }
    }

    $idsRaw = Get-RunningSandboxIds
    $ids = if ($null -eq $idsRaw) { @() } else { @($idsRaw) }
    if ($ids.Count -gt 0 -and -not [string]::IsNullOrWhiteSpace([string]$ids[0])) {
        return [string]$ids[0]
    }

    throw '시작한 Sandbox ID 를 얻지 못했다'
}

function Stop-TestSandbox {
    param([string]$Id)

    $null = Invoke-Wsb -Arguments @('stop', '--id', $Id)
}

function Read-ProgressLinesSafe {
    param([string]$ResolvedPath)

    if (-not (Test-Path -LiteralPath $ResolvedPath -PathType Leaf)) {
        return $null
    }

    try {
        $fs = [System.IO.FileStream]::new(
            $ResolvedPath,
            [System.IO.FileMode]::Open,
            [System.IO.FileAccess]::Read,
            [System.IO.FileShare]::ReadWrite
        )
        try {
            $sr = [System.IO.StreamReader]::new($fs, [System.Text.Encoding]::UTF8, $true)
            try {
                $lines = [System.Collections.Generic.List[string]]::new()
                while ($null -ne ($line = $sr.ReadLine())) {
                    $lines.Add($line)
                }
                return ,([string[]]$lines.ToArray())
            } finally {
                $sr.Dispose()
            }
        } finally {
            $fs.Dispose()
        }
    } catch [System.IO.IOException] {
        return $null
    }
}

function Wait-SandboxResult {
    # result.json 이 생기면 $true, 시간이 다 되면 $false. 기다리는 동안 progress.log 의 새 줄을 출력한다
    param(
        [string]$OutDir,
        [TimeSpan]$Timeout,
        [double]$PollSeconds = 15
    )

    $resultPath = Join-Path $OutDir 'result.json'
    $progressPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath((Join-Path $OutDir 'progress.log'))
    $linesRead = 0
    $sw = [System.Diagnostics.Stopwatch]::StartNew()

    while ($true) {
        $allLines = Read-ProgressLinesSafe -ResolvedPath $progressPath
        if ($null -ne $allLines -and $allLines.Count -gt $linesRead) {
            for ($i = $linesRead; $i -lt $allLines.Count; $i++) {
                Write-Host "  [Sandbox] $($allLines[$i])"
            }
            $linesRead = $allLines.Count
        }

        if (Test-Path -LiteralPath $resultPath -PathType Leaf) {
            return $true
        }

        if ($sw.Elapsed -ge $Timeout) {
            return $false
        }

        $remainingMs = ($Timeout - $sw.Elapsed).TotalMilliseconds
        $sleepMs = [int][Math]::Ceiling([Math]::Min($PollSeconds * 1000.0, $remainingMs))
        if ($sleepMs -lt 1) {
            $sleepMs = 1
        }
        Start-Sleep -Milliseconds $sleepMs
    }
}

function Get-DeclarationProblemsFromException {
    param($Exception)

    $ex = $Exception
    while ($null -ne $ex) {
        if ($ex.GetType().Name -eq 'DeclarationException' -or $ex.PSObject.Properties['Problems']) {
            return $ex.Problems
        }
        $ex = $ex.InnerException
    }
    return $null
}

function ConvertTo-NormalizedSkipList {
    param([string[]]$Skip)

    $list = [System.Collections.Generic.List[string]]::new()
    if ($null -ne $Skip) {
        foreach ($item in $Skip) {
            foreach ($part in ($item -split ',')) {
                $trimmed = $part.Trim()
                if ($trimmed -ne '') {
                    $list.Add($trimmed)
                }
            }
        }
    }
    return ,([string[]]$list.ToArray())
}

function Invoke-SandboxHarness {
    # → 종료 코드: 0 합격, 1 불합격(시간 초과 포함), 2 시작 못 함
    param(
        [Parameter(Mandatory)][string]$RepoRoot,
        [string[]]$Skip = @(),
        [int]$TimeoutMinutes = 90,
        [string]$BaseDir = (Join-Path $env:TEMP 'pc-setup-sandbox')
    )

    # 1. 실행 중인 Sandbox 확인
    $runningRaw = Get-RunningSandboxIds
    $runningIds = if ($null -eq $runningRaw) { @() } else { @($runningRaw | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }) }
    if ($runningIds.Count -gt 0) {
        Write-Host '실패: Sandbox 사용 중'
        return 2
    }

    $resolvedRepo = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($RepoRoot)
    $resolvedBaseDir = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($BaseDir)
    $pcSetupRoot = Join-Path $resolvedRepo 'pc-setup'

    # 2. 선언·예상 결과·-Skip 검사
    try {
        $setupItemsRaw = Get-SetupItems -Root $pcSetupRoot
        $setupItems = if ($null -eq $setupItemsRaw) { @() } else { @($setupItemsRaw) }
    } catch {
        $problems = Get-DeclarationProblemsFromException -Exception $_.Exception
        if ($null -ne $problems) {
            Write-Host '선언 오류:'
            foreach ($p in $problems) {
                Write-Host "  $p"
            }
            return 2
        }
        throw
    }

    $declaredIds = [string[]]@(
        foreach ($item in $setupItems) {
            $idVal = if ($item -is [System.Collections.IDictionary]) { $item['Id'] } else { $item.Id }
            if (-not [string]::IsNullOrEmpty($idVal)) {
                [string]$idVal
            }
        }
    )

    $expectedPath = Join-Path $pcSetupRoot 'test' 'sandbox-expected.psd1'
    try {
        $expectedItemsRaw = Read-SandboxExpected -Path $expectedPath
        if ($null -eq $expectedItemsRaw) {
            $expectedItems = [object[]]@()
        } else {
            $expectedItems = [object[]]@($expectedItemsRaw)
        }
    } catch {
        $problems = Get-DeclarationProblemsFromException -Exception $_.Exception
        if ($null -ne $problems) {
            foreach ($p in $problems) {
                Write-Host $p
            }
            return 2
        }
        throw
    }

    $expectedProblemsRaw = Test-SandboxExpectedIds -Expected $expectedItems -DeclaredIds $declaredIds
    $expectedProblems = if ($null -eq $expectedProblemsRaw) { @() } else { @($expectedProblemsRaw) }
    if ($expectedProblems.Count -gt 0) {
        foreach ($p in $expectedProblems) {
            Write-Host $p
        }
        return 2
    }

    $userSkip = ConvertTo-NormalizedSkipList -Skip $Skip
    $knownIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($id in $declaredIds) {
        $null = $knownIds.Add($id)
    }
    foreach ($skipId in $userSkip) {
        if (-not $knownIds.Contains($skipId)) {
            Write-Host "모르는 -Skip Id: $skipId"
            return 2
        }
    }

    # 3. 커밋하지 않은 변경 경고
    $prevEap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $gitStatus = & git -C $resolvedRepo status --porcelain 2>&1
        $statusExit = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $prevEap
    }
    if ($statusExit -ne 0) {
        throw "git status 실패 (종료 코드 $statusExit): $($gitStatus -join "`n")"
    }
    if (@($gitStatus | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }).Count -gt 0) {
        Write-Host '경고: 커밋하지 않은 변경은 시험되지 않는다'
    }

    # 4. 건너뛸 Id 합치기 (예상 결과 '건너뜀' 다음 사람 -Skip, 중복은 처음 것만)
    $expectedSkipRaw = Get-SandboxSkipIds -Expected $expectedItems
    $expectedSkipIds = if ($null -eq $expectedSkipRaw) { @() } else { @($expectedSkipRaw) }
    $mergedSkip = [System.Collections.Generic.List[string]]::new()
    $seenSkip = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($id in @($expectedSkipIds) + @($userSkip)) {
        if (-not [string]::IsNullOrWhiteSpace($id) -and $seenSkip.Add($id)) {
            $mergedSkip.Add($id)
        }
    }

    # 5. 실행 폴더·매핑 폴더·HEAD 번들·run.psd1·sandbox.wsb 준비
    $stamp = (Get-Date).ToString('yyyyMMdd-HHmmss')
    $runDir = Join-Path $resolvedBaseDir $stamp
    $inDir = Join-Path $runDir 'in'
    $outDir = Join-Path $runDir 'out'
    New-Item -Path $inDir -ItemType Directory -Force | Out-Null
    New-Item -Path $outDir -ItemType Directory -Force | Out-Null

    Export-HeadFiles -RepoRoot $resolvedRepo -InDir $inDir

    $skipLiterals = if ($mergedSkip.Count -gt 0) {
        ($mergedSkip | ForEach-Object { "'$($_.Replace("'", "''"))'" }) -join ', '
    } else {
        ''
    }
    $runPsd1Content = "@{`n    Skip = @($skipLiterals)`n}`n"
    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllText((Join-Path $inDir 'run.psd1'), $runPsd1Content, $utf8NoBom)

    $wsbConfig = New-WsbConfig -InDir $inDir -OutDir $outDir
    [System.IO.File]::WriteAllText((Join-Path $runDir 'sandbox.wsb'), $wsbConfig, $utf8NoBom)

    # 6. Sandbox 시작
    $sandboxId = Start-TestSandbox -Config $wsbConfig
    Write-Host "Sandbox 시작: $sandboxId"
    Write-Host "로그: $runDir"

    try {
        # 7. 결과 대기
        $gotResult = Wait-SandboxResult -OutDir $outDir -Timeout ([TimeSpan]::FromMinutes($TimeoutMinutes))
        if (-not $gotResult) {
            Write-Host "실패: 시간 초과 (${TimeoutMinutes}분)"
            return 1
        }

        # 8. result.json 판정 및 report.txt 저장
        $resultJsonPath = Join-Path $outDir 'result.json'
        $runObj = $null
        try {
            $rawJson = [System.IO.File]::ReadAllText($resultJsonPath, [System.Text.Encoding]::UTF8)
            if ([string]::IsNullOrWhiteSpace($rawJson)) {
                throw 'empty'
            }
            $runObj = $rawJson | ConvertFrom-Json -ErrorAction Stop
            if ($null -eq $runObj) {
                throw 'null'
            }
        } catch {
            Write-Host '실패: result.json 을 읽지 못했다'
            return 1
        }

        $judgment = Test-SandboxRun -Run $runObj -Expected $expectedItems
        $reportLinesRaw = Format-SandboxReport -Judgment $judgment
        $reportLines = if ($null -eq $reportLinesRaw) { @() } else { @($reportLinesRaw) }
        foreach ($line in $reportLines) {
            Write-Host $line
        }
        [System.IO.File]::WriteAllLines((Join-Path $runDir 'report.txt'), [string[]]$reportLines, $utf8NoBom)

        if ($judgment.Passed) {
            return 0
        }
        return 1
    } catch {
        Write-Host "실패: $($_.Exception.Message)"
        return 1
    } finally {
        # 9. 어떤 경로로 끝나든 Stop-TestSandbox 1번 호출, 실패 시 경고만 출력
        if (-not [string]::IsNullOrWhiteSpace($sandboxId)) {
            try {
                $null = Stop-TestSandbox -Id $sandboxId
            } catch {
                Write-Warning "Sandbox 종료 실패 ($sandboxId): $($_.Exception.Message)"
            }
        }
    }
}

Export-ModuleMember -Function Invoke-Wsb, Get-RunningSandboxIds, Export-HeadFiles, New-WsbConfig, Start-TestSandbox, Stop-TestSandbox, Wait-SandboxResult, Invoke-SandboxHarness
