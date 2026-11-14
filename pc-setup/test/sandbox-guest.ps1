# pc-setup/test/sandbox-guest.ps1 — Windows PowerShell 5.1
[CmdletBinding()]
param(
    [string]$InDir = 'C:\pcs\in',
    [string]$OutDir = 'C:\pcs\out'
)

function Test-AdminWindow {
    $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [System.Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Enable-TestUac {
    $regPath = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'
    Set-ItemProperty -LiteralPath $regPath -Name 'EnableLUA' -Value 1 -Type DWord -Force -ErrorAction Stop
    Set-ItemProperty -LiteralPath $regPath -Name 'ConsentPromptBehaviorAdmin' -Value 0 -Type DWord -Force -ErrorAction Stop
}

function Restart-Guest {
    Restart-Computer -Force
}

function Invoke-Child {
    param([string]$FilePath, [string[]]$Arguments)
    if ($null -ne $Arguments -and $Arguments.Count -gt 0) {
        & $FilePath @Arguments | Out-Default
    } else {
        & $FilePath | Out-Default
    }
    return [int]$LASTEXITCODE
}

function Update-SessionPath {
    $machinePath = [System.Environment]::GetEnvironmentVariable('Path', [System.EnvironmentVariableTarget]::Machine)
    $userPath = [System.Environment]::GetEnvironmentVariable('Path', [System.EnvironmentVariableTarget]::User)
    $parts = @()
    if (-not [string]::IsNullOrEmpty($machinePath)) { $parts += $machinePath }
    if (-not [string]::IsNullOrEmpty($userPath)) { $parts += $userPath }
    $env:Path = $parts -join ';'
}

function Get-GuestRepoPath {
    $val = [System.Environment]::GetEnvironmentVariable('ANYTHING_REPO', [System.EnvironmentVariableTarget]::User)
    if (-not [string]::IsNullOrWhiteSpace($val)) {
        return [string]$val
    }
    return (Join-Path $HOME 'anything')
}

function Write-GuestProgress {
    param([string]$OutDir, [string]$Message)
    $logPath = Join-Path $OutDir 'progress.log'
    $stamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    Add-Content -LiteralPath $logPath -Value "$stamp $Message" -Encoding UTF8 -ErrorAction Stop
}

function Read-JsonOrNull {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $null
    }
    try {
        $raw = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
        if ([string]::IsNullOrWhiteSpace($raw)) {
            return $null
        }
        return ($raw | ConvertFrom-Json)
    } catch {
        return $null
    }
}

function Write-GuestResult {
    param([string]$OutDir, $Result)
    $tmpPath = Join-Path $OutDir 'result.json.tmp'
    $finalPath = Join-Path $OutDir 'result.json'
    $resolvedTmp = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($tmpPath)
    $json = $Result | ConvertTo-Json -Depth 20
    [System.IO.File]::WriteAllText($resolvedTmp, $json, [System.Text.Encoding]::UTF8)
    Move-Item -LiteralPath $tmpPath -Destination $finalPath -Force -ErrorAction Stop
}

function Invoke-Guest {
    param([string]$InDir, [string]$OutDir)

    $statePath = Join-Path $OutDir 'state.txt'
    $state = ''
    if (Test-Path -LiteralPath $statePath -PathType Leaf) {
        $rawState = Get-Content -LiteralPath $statePath -Raw -Encoding UTF8
        if ($null -ne $rawState) {
            $state = $rawState.Trim()
        }
    }

    if ($state -eq '') {
        Write-GuestProgress -OutDir $OutDir -Message 'UAC 켜고 재시작'
        Enable-TestUac
        Set-Content -LiteralPath $statePath -Value 'uac' -NoNewline -Encoding ASCII -ErrorAction Stop
        Restart-Guest
        return
    }

    if ($state -eq 'done') {
        return
    }

    if ($state -eq 'running') {
        Write-GuestResult -OutDir $OutDir -Result ([ordered]@{
            Error = '셋업 중 Sandbox 가 다시 시작됐다'
            Runs  = @()
        })
        Set-Content -LiteralPath $statePath -Value 'done' -NoNewline -Encoding ASCII -ErrorAction Stop
        return
    }

    if ($state -eq 'uac') {
        if (Test-AdminWindow) {
            Write-GuestResult -OutDir $OutDir -Result ([ordered]@{
                Error = 'UAC 를 켠 뒤에도 관리자 권한으로 돈다'
                Runs  = @()
            })
            Set-Content -LiteralPath $statePath -Value 'done' -NoNewline -Encoding ASCII -ErrorAction Stop
            return
        }

        Set-Content -LiteralPath $statePath -Value 'running' -NoNewline -Encoding ASCII -ErrorAction Stop
        $runs = [System.Collections.Generic.List[object]]::new()
        $transcriptStarted = $false
        $transcriptPath = Join-Path $OutDir 'transcript.txt'

        try {
            Start-Transcript -LiteralPath $transcriptPath -ErrorAction Stop | Out-Null
            $transcriptStarted = $true

            $skipIds = [System.Collections.Generic.List[string]]::new()
            $runConfigPath = Join-Path $InDir 'run.psd1'
            if (Test-Path -LiteralPath $runConfigPath -PathType Leaf) {
                $runData = Import-PowerShellDataFile -LiteralPath $runConfigPath -ErrorAction Stop
                if ($null -ne $runData -and $runData.ContainsKey('Skip') -and $null -ne $runData['Skip']) {
                    foreach ($item in $runData['Skip']) {
                        foreach ($part in ([string]$item -split ',')) {
                            $trimmed = $part.Trim()
                            if ($trimmed -ne '') {
                                $skipIds.Add($trimmed)
                            }
                        }
                    }
                }
            }

            $bootstrapScript = Join-Path $InDir 'bootstrap.ps1'
            $bundlePath = Join-Path $InDir 'repo.bundle'
            $bootstrapJsonPath = Join-Path $OutDir 'bootstrap.json'
            $setup1JsonPath = Join-Path $OutDir 'setup-1.json'

            $bootArgs = [System.Collections.Generic.List[string]]::new()
            $bootArgs.Add('-NoProfile')
            $bootArgs.Add('-ExecutionPolicy')
            $bootArgs.Add('Bypass')
            $bootArgs.Add('-File')
            $bootArgs.Add($bootstrapScript)
            $bootArgs.Add('-Source')
            $bootArgs.Add($bundlePath)
            $bootArgs.Add('-ResultPath')
            $bootArgs.Add($bootstrapJsonPath)
            $bootArgs.Add('-SetupResultPath')
            $bootArgs.Add($setup1JsonPath)
            if ($skipIds.Count -gt 0) {
                $bootArgs.Add('-Skip')
                $bootArgs.Add(($skipIds -join ','))
            }

            Write-GuestProgress -OutDir $OutDir -Message 'bootstrap 시작'
            $bootExit = Invoke-Child -FilePath 'powershell.exe' -Arguments ([string[]]$bootArgs.ToArray())
            Write-GuestProgress -OutDir $OutDir -Message "bootstrap 끝 ($bootExit)"

            $runs.Add([ordered]@{
                Name     = 'bootstrap'
                ExitCode = $bootExit
                Result   = (Read-JsonOrNull -Path $bootstrapJsonPath)
            })

            $hasSetup1 = Test-Path -LiteralPath $setup1JsonPath -PathType Leaf
            if ($hasSetup1) {
                $runs.Add([ordered]@{
                    Name     = 'setup-1'
                    ExitCode = $bootExit
                    Result   = (Read-JsonOrNull -Path $setup1JsonPath)
                })

                Update-SessionPath
                $repoPath = Get-GuestRepoPath
                $setupScript = Join-Path $repoPath 'pc-setup\setup.ps1'
                $setup2JsonPath = Join-Path $OutDir 'setup-2.json'

                $pwshCmd = Get-Command 'pwsh' -ErrorAction SilentlyContinue
                $pwshExe = if ($null -ne $pwshCmd) {
                    $pwshCmd.Source
                } else {
                    Join-Path $env:ProgramFiles 'PowerShell\7\pwsh.exe'
                }

                $setup2Args = [System.Collections.Generic.List[string]]::new()
                $setup2Args.Add('-NoProfile')
                $setup2Args.Add('-File')
                $setup2Args.Add($setupScript)
                $setup2Args.Add('-ResultPath')
                $setup2Args.Add($setup2JsonPath)
                if ($skipIds.Count -gt 0) {
                    $setup2Args.Add('-Skip')
                    $setup2Args.Add(($skipIds -join ','))
                }

                Write-GuestProgress -OutDir $OutDir -Message 'setup-2 시작'
                $setup2Exit = Invoke-Child -FilePath $pwshExe -Arguments ([string[]]$setup2Args.ToArray())
                Write-GuestProgress -OutDir $OutDir -Message "setup-2 끝 ($setup2Exit)"

                $runs.Add([ordered]@{
                    Name     = 'setup-2'
                    ExitCode = $setup2Exit
                    Result   = (Read-JsonOrNull -Path $setup2JsonPath)
                })
            }

            Write-GuestResult -OutDir $OutDir -Result ([ordered]@{
                Error = ''
                Runs  = [object[]]$runs.ToArray()
            })
            if ($transcriptStarted) {
                try { Stop-Transcript | Out-Null } catch {}
                $transcriptStarted = $false
            }
            Set-Content -LiteralPath $statePath -Value 'done' -NoNewline -Encoding ASCII -ErrorAction Stop
            Write-GuestProgress -OutDir $OutDir -Message '끝'
        } catch {
            $errMsg = $_.Exception.Message
            if ($transcriptStarted) {
                try { Stop-Transcript | Out-Null } catch {}
                $transcriptStarted = $false
            }
            Write-GuestResult -OutDir $OutDir -Result ([ordered]@{
                Error = $errMsg
                Runs  = [object[]]$runs.ToArray()
            })
            Set-Content -LiteralPath $statePath -Value 'done' -NoNewline -Encoding ASCII -ErrorAction Stop
        } finally {
            if ($transcriptStarted) {
                try { Stop-Transcript | Out-Null } catch {}
                $transcriptStarted = $false
            }
        }
    }
}

Invoke-Guest -InDir $InDir -OutDir $OutDir
