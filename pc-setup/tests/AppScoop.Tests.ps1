BeforeAll {
    $envPathModule = Join-Path $PSScriptRoot '..' 'lib' 'EnvPath.psm1'
    Import-Module $envPathModule -Force
    $elevationModule = Join-Path $PSScriptRoot '..' 'lib' 'Elevation.psm1'
    Import-Module $elevationModule -Force
    $appScoopModule = Join-Path $PSScriptRoot '..' 'lib' 'AppScoop.psm1'
    Import-Module $appScoopModule -Force
}

Describe 'Invoke-ScoopApp' {
    It '1: scoop 있음, 버킷 있음, 앱 있음 -> 그대로, install·bucket add 안 불림 (-Check <Check>)' -ForEach @(
        @{ Check = $false }
        @{ Check = $true }
    ) {
        $script:calls = [System.Collections.Generic.List[string]]::new()
        Mock -ModuleName AppScoop Invoke-Scoop {
            $script:calls.Add(($Arguments -join ' '))
            switch ($Arguments[0]) {
                '--version' { return @{ ExitCode = 0; Output = @('v0.6.0') } }
                'bucket'    { return @{ ExitCode = 0; Output = @([pscustomobject]@{ Name = 'main' }, [pscustomobject]@{ Name = 'extras' }) } }
                'prefix'    { return @{ ExitCode = 0; Output = @('C:\Users\test\scoop\apps\lazygit\current') } }
                default     { throw "예상치 못한 호출: $($Arguments -join ' ')" }
            }
        }
        Mock -ModuleName AppScoop Install-Scoop { throw 'Install-Scoop 이 불리면 안 됩니다' }
        Mock -ModuleName AppScoop Update-SessionPath { throw 'Update-SessionPath 가 불리면 안 됩니다' }

        $entry = [pscustomobject]@{ Id = 'lazygit'; Bucket = 'extras' }
        $res = Invoke-ScoopApp -Entry $entry -Check $Check

        $res.Status | Should -Be '그대로'
        $res.Detail | Should -Be ''
        $script:calls | Should -Not -Contain 'bucket add extras'
        $script:calls | Should -Not -Contain 'install extras/lazygit'
    }

    It '2: 앱 없음, -Check $true -> 다름 (설치 안 됨)' {
        Mock -ModuleName AppScoop Invoke-Scoop {
            switch ($Arguments[0]) {
                '--version' { return @{ ExitCode = 0; Output = @('v0.6.0') } }
                'bucket'    { return @{ ExitCode = 0; Output = @([pscustomobject]@{ Name = 'extras' }) } }
                'prefix'    { return @{ ExitCode = 1; Output = @("Could not find app path for 'lazygit'.") } }
                default     { throw "예상치 못한 호출: $($Arguments -join ' ')" }
            }
        }
        Mock -ModuleName AppScoop Install-Scoop {}
        Mock -ModuleName AppScoop Update-SessionPath {}

        $entry = [pscustomobject]@{ Id = 'lazygit'; Bucket = 'extras' }
        $res = Invoke-ScoopApp -Entry $entry -Check $true

        $res.Status | Should -Be '다름'
        $res.Detail | Should -Be '설치 안 됨'
    }

    It '3: 앱 없음, install 0 -> 바꿈, install 인자 install extras/lazygit, Update-SessionPath 불림' {
        $script:installArgs = $null
        $script:pathCalls = 0
        Mock -ModuleName AppScoop Invoke-Scoop {
            switch ($Arguments[0]) {
                '--version' { return @{ ExitCode = 0; Output = @('v0.6.0') } }
                'bucket'    { return @{ ExitCode = 0; Output = @([pscustomobject]@{ Name = 'extras' }) } }
                'prefix'    { return @{ ExitCode = 1; Output = @() } }
                'install'   {
                    $script:installArgs = $Arguments
                    return @{ ExitCode = 0; Output = @() }
                }
                default     { throw "예상치 못한 호출: $($Arguments -join ' ')" }
            }
        }
        Mock -ModuleName AppScoop Install-Scoop {}
        Mock -ModuleName AppScoop Update-SessionPath { $script:pathCalls++ }

        $entry = [pscustomobject]@{ Id = 'lazygit'; Bucket = 'extras' }
        $res = Invoke-ScoopApp -Entry $entry -Check $false

        $res.Status | Should -Be '바꿈'
        $res.Detail | Should -Be ''
        ($script:installArgs -join ' ') | Should -Be 'install extras/lazygit'
        $script:pathCalls | Should -Be 1
    }

    It '4: 버킷 없음, -Check $true -> 다름 (버킷 extras 없음)' {
        Mock -ModuleName AppScoop Invoke-Scoop {
            switch ($Arguments[0]) {
                '--version' { return @{ ExitCode = 0; Output = @('v0.6.0') } }
                'bucket'    { return @{ ExitCode = 0; Output = @([pscustomobject]@{ Name = 'main' }) } }
                default     { throw "예상치 못한 호출: $($Arguments -join ' ')" }
            }
        }
        Mock -ModuleName AppScoop Install-Scoop {}
        Mock -ModuleName AppScoop Update-SessionPath {}

        $entry = [pscustomobject]@{ Id = 'lazygit'; Bucket = 'extras' }
        $res = Invoke-ScoopApp -Entry $entry -Check $true

        $res.Status | Should -Be '다름'
        $res.Detail | Should -Be '버킷 extras 없음'
    }

    It '5: 버킷 없음, 앱 없음 -> bucket add -> install 순서, 바꿈' {
        $script:calls = [System.Collections.Generic.List[string]]::new()
        Mock -ModuleName AppScoop Invoke-Scoop {
            $script:calls.Add(($Arguments -join ' '))
            switch ($Arguments[0]) {
                '--version' { return @{ ExitCode = 0; Output = @('v0.6.0') } }
                'bucket' {
                    if ($Arguments[1] -eq 'list') {
                        return @{ ExitCode = 0; Output = @([pscustomobject]@{ Name = 'main' }) }
                    }
                    return @{ ExitCode = 0; Output = @() }
                }
                'prefix'  { return @{ ExitCode = 1; Output = @() } }
                'install' { return @{ ExitCode = 0; Output = @() } }
                default   { throw "예상치 못한 호출: $($Arguments -join ' ')" }
            }
        }
        Mock -ModuleName AppScoop Install-Scoop {}
        Mock -ModuleName AppScoop Update-SessionPath {}

        $entry = [pscustomobject]@{ Id = 'lazygit'; Bucket = 'extras' }
        $res = Invoke-ScoopApp -Entry $entry -Check $false

        $res.Status | Should -Be '바꿈'
        $res.Detail | Should -Be ''
        $addIdx = $script:calls.IndexOf('bucket add extras')
        $installIdx = $script:calls.IndexOf('install extras/lazygit')
        $addIdx | Should -BeGreaterOrEqual 0
        $installIdx | Should -BeGreaterThan $addIdx
    }

    It '6: bucket add 실패 -> 실패, install 안 불림' {
        $script:installCalled = $false
        Mock -ModuleName AppScoop Invoke-Scoop {
            switch ($Arguments[0]) {
                '--version' { return @{ ExitCode = 0; Output = @('v0.6.0') } }
                'bucket' {
                    if ($Arguments[1] -eq 'list') {
                        return @{ ExitCode = 0; Output = @([pscustomobject]@{ Name = 'main' }) }
                    }
                    return @{ ExitCode = 1; Output = @() }
                }
                'install' {
                    $script:installCalled = $true
                    return @{ ExitCode = 0; Output = @() }
                }
                default { throw "예상치 못한 호출: $($Arguments -join ' ')" }
            }
        }
        Mock -ModuleName AppScoop Install-Scoop {}
        Mock -ModuleName AppScoop Update-SessionPath {}

        $entry = [pscustomobject]@{ Id = 'lazygit'; Bucket = 'extras' }
        $res = Invoke-ScoopApp -Entry $entry -Check $false

        $res.Status | Should -Be '실패'
        $res.Detail | Should -Be 'scoop bucket add extras 종료 코드 1'
        $script:installCalled | Should -BeFalse
    }

    It '7: scoop 없음, -Check $true -> 다름 (scoop 없음), Install-Scoop 안 불림' {
        $script:installScoopCalled = $false
        Mock -ModuleName AppScoop Invoke-Scoop {
            if ($Arguments[0] -eq '--version') {
                return @{ ExitCode = $null; Output = @() }
            }
            throw "예상치 못한 호출: $($Arguments -join ' ')"
        }
        Mock -ModuleName AppScoop Install-Scoop {
            $script:installScoopCalled = $true
            return $true
        }
        Mock -ModuleName AppScoop Update-SessionPath {}

        $entry = [pscustomobject]@{ Id = 'lazygit'; Bucket = 'extras' }
        $res = Invoke-ScoopApp -Entry $entry -Check $true

        $res.Status | Should -Be '다름'
        $res.Detail | Should -Be 'scoop 없음'
        $script:installScoopCalled | Should -BeFalse
    }

    It '8: scoop 없음, -Check $false -> Install-Scoop -> bucket add -> install, 바꿈' {
        $script:steps = [System.Collections.Generic.List[string]]::new()
        $script:pathCalls = 0
        Mock -ModuleName AppScoop Install-Scoop {
            $script:steps.Add('install-scoop')
            return $true
        }
        Mock -ModuleName AppScoop Invoke-Scoop {
            switch ($Arguments[0]) {
                '--version' { return @{ ExitCode = $null; Output = @() } }
                'bucket' {
                    if ($Arguments[1] -eq 'list') {
                        return @{ ExitCode = 0; Output = @([pscustomobject]@{ Name = 'main' }) }
                    }
                    $script:steps.Add('bucket-add')
                    return @{ ExitCode = 0; Output = @() }
                }
                'prefix' { return @{ ExitCode = 1; Output = @() } }
                'install' {
                    $script:steps.Add('install-app')
                    return @{ ExitCode = 0; Output = @() }
                }
                default { throw "예상치 못한 호출: $($Arguments -join ' ')" }
            }
        }
        Mock -ModuleName AppScoop Update-SessionPath { $script:pathCalls++ }

        $entry = [pscustomobject]@{ Id = 'lazygit'; Bucket = 'extras' }
        $res = Invoke-ScoopApp -Entry $entry -Check $false

        $res.Status | Should -Be '바꿈'
        $res.Detail | Should -Be ''
        ($script:steps -join ',') | Should -Be 'install-scoop,bucket-add,install-app'
        $script:pathCalls | Should -Be 2
    }

    It '9: Install-Scoop 이 $false -> 실패: scoop 설치 실패' {
        Mock -ModuleName AppScoop Invoke-Scoop {
            if ($Arguments[0] -eq '--version') {
                return @{ ExitCode = $null; Output = @() }
            }
            throw "예상치 못한 호출: $($Arguments -join ' ')"
        }
        Mock -ModuleName AppScoop Install-Scoop { return $false }
        Mock -ModuleName AppScoop Update-SessionPath {}

        $entry = [pscustomobject]@{ Id = 'lazygit'; Bucket = 'extras' }
        $res = Invoke-ScoopApp -Entry $entry -Check $false

        $res.Status | Should -Be '실패'
        $res.Detail | Should -Be 'scoop 설치 실패'
    }

    It '10: install 종료 코드 1 -> 실패: scoop install main/cmake 종료 코드 1' {
        Mock -ModuleName AppScoop Invoke-Scoop {
            switch ($Arguments[0]) {
                '--version' { return @{ ExitCode = 0; Output = @('v0.6.0') } }
                'bucket'    { return @{ ExitCode = 0; Output = @([pscustomobject]@{ Name = 'main' }) } }
                'prefix'    { return @{ ExitCode = 1; Output = @() } }
                'install'   { return @{ ExitCode = 1; Output = @() } }
                default     { throw "예상치 못한 호출: $($Arguments -join ' ')" }
            }
        }
        Mock -ModuleName AppScoop Install-Scoop {}
        Mock -ModuleName AppScoop Update-SessionPath {}

        $entry = [pscustomobject]@{ Id = 'cmake'; Bucket = 'main' }
        $res = Invoke-ScoopApp -Entry $entry -Check $false

        $res.Status | Should -Be '실패'
        $res.Detail | Should -Be 'scoop install main/cmake 종료 코드 1'
    }

    It '11: 버킷만 없고 앱은 있음 -> bucket add 후 바꿈' {
        $script:calls = [System.Collections.Generic.List[string]]::new()
        Mock -ModuleName AppScoop Invoke-Scoop {
            $script:calls.Add(($Arguments -join ' '))
            switch ($Arguments[0]) {
                '--version' { return @{ ExitCode = 0; Output = @('v0.6.0') } }
                'bucket' {
                    if ($Arguments[1] -eq 'list') {
                        return @{ ExitCode = 0; Output = @([pscustomobject]@{ Name = 'main' }) }
                    }
                    return @{ ExitCode = 0; Output = @() }
                }
                'prefix' { return @{ ExitCode = 0; Output = @('C:\Users\test\scoop\apps\lazygit\current') } }
                default  { throw "예상치 못한 호출: $($Arguments -join ' ')" }
            }
        }
        Mock -ModuleName AppScoop Install-Scoop {}
        Mock -ModuleName AppScoop Update-SessionPath {}

        $entry = [pscustomobject]@{ Id = 'lazygit'; Bucket = 'extras' }
        $res = Invoke-ScoopApp -Entry $entry -Check $false

        $res.Status | Should -Be '바꿈'
        $res.Detail | Should -Be ''
        $script:calls | Should -Contain 'bucket add extras'
        $script:calls | Should -Not -Contain 'install extras/lazygit'
    }
}

Describe 'Invoke-Scoop' {
    It 'Get-Command scoop 이 없으면 ExitCode $null 을 돌려준다' {
        Mock -ModuleName AppScoop Get-Command { return $null }

        $res = Invoke-Scoop -Arguments @('--version')

        $null -eq $res.ExitCode | Should -BeTrue
        $res.Output.Count | Should -Be 0
    }
}

Describe 'Install-Scoop' {
    It '관리자 창이면 설치하지 않고 $false 를 돌려준다' {
        Mock -ModuleName AppScoop Test-AdminWindow { return $true }
        Mock -ModuleName AppScoop Invoke-RestMethod { throw '호출되면 안 됩니다' }

        $res = Install-Scoop

        $res | Should -BeFalse
    }

    It '설치 스크립트가 비종료 오류(Write-Error)를 내면 $false 를 돌려준다' {
        Mock -ModuleName AppScoop Test-AdminWindow { return $false }
        Mock -ModuleName AppScoop Invoke-RestMethod { return "Write-Error 'install failed'" }

        $res = Install-Scoop

        $res | Should -BeFalse
    }
}
