using module ../lib/ItemScript.psm1

BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..' 'lib' 'ItemScript.psm1'
    Import-Module $modulePath -Force
}

Describe 'Invoke-ItemScript 표 1~9' {
    It '1: Write-Output 그대로 -> 그대로' {
        Set-Content -Path 'TestDrive:/case1.ps1' -Value "Write-Output '그대로'"
        $res = Invoke-ItemScript -Path 'TestDrive:/case1.ps1'
        $res.Status | Should -Be '그대로'
        $res.Detail | Should -Be ''
    }

    It '2: 여러 줄 출력 뒤 마지막 줄 바꿈 (x) -> 바꿈, Detail x (앞 줄은 무시)' {
        $content = @"
Write-Output '첫 번째 줄'
Write-Output '두 번째 줄'
Write-Output '바꿈 (x)'
"@
        Set-Content -Path 'TestDrive:/case2.ps1' -Value $content
        $res = Invoke-ItemScript -Path 'TestDrive:/case2.ps1'
        $res.Status | Should -Be '바꿈'
        $res.Detail | Should -Be 'x'
    }

    It '3: -Check 를 받아 다름 을 낸다 -> -Check 로 부르면 다름' {
        $content = @"
param([switch]`$Check)
if (`$Check) {
    Write-Output '다름'
} else {
    Write-Output '그대로'
}
"@
        Set-Content -Path 'TestDrive:/case3.ps1' -Value $content
        $res = Invoke-ItemScript -Path 'TestDrive:/case3.ps1' -Check
        $res.Status | Should -Be '다름'
        $res.Detail | Should -Be ''

        $resNormal = Invoke-ItemScript -Path 'TestDrive:/case3.ps1'
        $resNormal.Status | Should -Be '그대로'
    }

    It '4: 출력 없음 -> 실패, Detail 결과 줄 없음' {
        Set-Content -Path 'TestDrive:/case4.ps1' -Value '# 빈 스크립트'
        $res = Invoke-ItemScript -Path 'TestDrive:/case4.ps1'
        $res.Status | Should -Be '실패'
        $res.Detail | Should -Be '결과 줄 없음'
    }

    It '5: 마지막 줄이 OK -> 실패, Detail 모르는 결과: OK' {
        Set-Content -Path 'TestDrive:/case5.ps1' -Value "Write-Output 'OK'"
        $res = Invoke-ItemScript -Path 'TestDrive:/case5.ps1'
        $res.Status | Should -Be '실패'
        $res.Detail | Should -Be '모르는 결과: OK'
    }

    It '6: throw 디스크 가득 -> 실패, Detail 디스크 가득' {
        Set-Content -Path 'TestDrive:/case6.ps1' -Value "throw '디스크 가득'"
        $res = Invoke-ItemScript -Path 'TestDrive:/case6.ps1'
        $res.Status | Should -Be '실패'
        $res.Detail | Should -Be '디스크 가득'
    }

    It '7: 파일이 없음 -> 실패, Detail 스크립트가 없다: <경로>' {
        $missingPath = 'TestDrive:/not_found.ps1'
        $res = Invoke-ItemScript -Path $missingPath
        $res.Status | Should -Be '실패'
        $res.Detail | Should -Be "스크립트가 없다: $missingPath"
    }

    It '8: 마지막 출력이 문자열이 아닌 객체 뒤 문자열 -> 마지막 문자열 줄을 쓴다' {
        $content = @"
[pscustomobject]@{ Number = 42; Name = 'Test' }
Write-Output '그대로'
"@
        Set-Content -Path 'TestDrive:/case8.ps1' -Value $content
        $res = Invoke-ItemScript -Path 'TestDrive:/case8.ps1'
        $res.Status | Should -Be '그대로'
        $res.Detail | Should -Be ''
    }

    It '9: 스크립트가 exit 3 으로 끝나고 그 앞에 실패: x 출력 -> 실패, Detail x (종료 코드로 판정하지 않는다)' {
        $content = @"
Write-Output '실패: x'
exit 3
"@
        Set-Content -Path 'TestDrive:/case9.ps1' -Value $content
        $res = Invoke-ItemScript -Path 'TestDrive:/case9.ps1'
        $res.Status | Should -Be '실패'
        $res.Detail | Should -Be 'x'
    }
}
