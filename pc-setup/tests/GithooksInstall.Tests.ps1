Describe '.githooks/install.ps1' {
    BeforeAll {
        $script:sourceInstall = (Resolve-Path (Join-Path $PSScriptRoot '..' '..' '.githooks' 'install.ps1')).Path
        $script:repoCounter = 0

        function New-TempGitRepo {
            $script:repoCounter++
            $base = (Get-Item 'TestDrive:/').FullName
            $repoDir = Join-Path $base "repo-$($script:repoCounter)"
            $hooksDir = Join-Path $repoDir '.githooks'
            New-Item -Path $hooksDir -ItemType Directory -Force | Out-Null

            & git init $repoDir 2>$null | Out-Null
            if ($LASTEXITCODE -ne 0) {
                throw "git init 실패: 종료 코드 $LASTEXITCODE"
            }

            $installCopy = Join-Path $hooksDir 'install.ps1'
            Copy-Item -LiteralPath $script:sourceInstall -Destination $installCopy -Force

            return [pscustomobject]@{
                RepoDir     = $repoDir
                InstallPath = $installCopy
            }
        }
    }

    It '표 1: core.hooksPath 없음 -> -Check 는 다름 (없음) 이고 설정 안 바꿈, 고치는 실행은 바꿈' {
        $repo = New-TempGitRepo

        $checkOut = & $repo.InstallPath -Check
        $checkOut | Should -Be '다름 (없음)'

        & git -C $repo.RepoDir config --local --get core.hooksPath 2>$null | Out-Null
        $LASTEXITCODE | Should -Be 1

        $fixOut = & $repo.InstallPath
        $fixOut | Should -Be '바꿈'

        $val = & git -C $repo.RepoDir config --local --get core.hooksPath
        $LASTEXITCODE | Should -Be 0
        $val.Trim() | Should -Be '.githooks'
    }

    It '표 2: core.hooksPath 가 절대 경로 -> -Check 는 다름 (.githooks 가 아니다) (경로 미포함, 설정 유지), 고치는 실행은 바꿈' {
        $repo = New-TempGitRepo
        $absPath = 'C:\Users\secret-user\other-repo\.githooks'
        & git -C $repo.RepoDir config --local core.hooksPath $absPath
        $LASTEXITCODE | Should -Be 0

        $checkOut = & $repo.InstallPath -Check
        $checkOut | Should -Be '다름 (.githooks 가 아니다)'
        $checkOut | Should -Not -Match ([regex]::Escape($absPath))
        $checkOut | Should -Not -Match 'secret-user'

        $afterCheck = & git -C $repo.RepoDir config --local --get core.hooksPath
        $afterCheck.Trim() | Should -Be $absPath

        $fixOut = & $repo.InstallPath
        $fixOut | Should -Be '바꿈'

        $val = & git -C $repo.RepoDir config --local --get core.hooksPath
        $val.Trim() | Should -Be '.githooks'
    }

    It '표 3: core.hooksPath 가 .githooks -> -Check 와 고치는 실행 모두 그대로' {
        $repo = New-TempGitRepo
        & git -C $repo.RepoDir config --local core.hooksPath .githooks
        $LASTEXITCODE | Should -Be 0

        $checkOut = & $repo.InstallPath -Check
        $checkOut | Should -Be '그대로'

        $fixOut = & $repo.InstallPath
        $fixOut | Should -Be '그대로'
    }

    It '표 4: 고치는 실행 뒤 다시 고치는 실행 -> 그대로 (멱등)' {
        $repo = New-TempGitRepo

        $firstOut = & $repo.InstallPath
        $firstOut | Should -Be '바꿈'

        $secondOut = & $repo.InstallPath
        $secondOut | Should -Be '그대로'
    }

    It '표 5: git 이 PATH 에 없음 (빈 PATH 하위 프로세스) -> -Check 와 고치는 실행 모두 실패: git 이 없다' {
        $repo = New-TempGitRepo
        $psExe = (Get-Process -Id $PID).Path
        $origPath = $env:PATH
        # 스크립트는 UTF-8 로 출력하므로, 자식 출력을 UTF-8 로 읽는다.
        $savedOutputEncoding = [Console]::OutputEncoding

        try {
            [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
            $env:PATH = ''

            $checkOut = & $psExe -NoProfile -File $repo.InstallPath -Check
            $LASTEXITCODE | Should -Be 0
            $checkOut | Should -Be '실패: git 이 없다'

            $fixOut = & $psExe -NoProfile -File $repo.InstallPath
            $LASTEXITCODE | Should -Be 0
            $fixOut | Should -Be '실패: git 이 없다'
        } finally {
            $env:PATH = $origPath
            [Console]::OutputEncoding = $savedOutputEncoding
        }
    }

    It '출력 인코딩: 자식 pwsh -File 의 -Check 한 줄이 콘솔 코드 페이지(CP949)와 상관없이 BOM 없는 UTF-8 바이트다' {
        $repo = New-TempGitRepo
        $saved = [Console]::OutputEncoding
        try {
            [Console]::OutputEncoding = [System.Text.Encoding]::GetEncoding(949)
            $psi = [System.Diagnostics.ProcessStartInfo]::new('pwsh')
            foreach ($a in @('-NoProfile', '-File', $repo.InstallPath, '-Check')) {
                $psi.ArgumentList.Add($a)
            }
            $psi.RedirectStandardOutput = $true
            $psi.UseShellExecute = $false
            $proc = [System.Diagnostics.Process]::Start($psi)
            $ms = [System.IO.MemoryStream]::new()
            $proc.StandardOutput.BaseStream.CopyTo($ms)
            $proc.WaitForExit()
        } finally {
            [Console]::OutputEncoding = $saved
        }
        $proc.ExitCode | Should -Be 0
        $ms.ToArray() | Should -Be ([System.Text.UTF8Encoding]::new($false).GetBytes("다름 (없음)`r`n"))
    }

    It '출력 인코딩: 같은 프로세스에서 실행한 뒤 [Console]::OutputEncoding 이 원래 값으로 돌아온다' {
        $repo = New-TempGitRepo
        $saved = [Console]::OutputEncoding
        try {
            [Console]::OutputEncoding = [System.Text.Encoding]::GetEncoding(949)
            $out = & $repo.InstallPath -Check
            $out | Should -Be '다름 (없음)'
            [Console]::OutputEncoding.CodePage | Should -Be 949
        } finally {
            [Console]::OutputEncoding = $saved
        }
    }
}
