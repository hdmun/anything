<#
.SYNOPSIS
    ssh-notify 를 NAS 에 올리고 install.sh 를 부른다 (설치·다시 올리기·제거).

.DESCRIPTION
    1. 파일을 tar 로 묶어 ssh 로 보내고, NAS 의 ~/ssh-notify-upload/ 에 푼다.
    2. ssh -t <별칭> sudo sh ~/ssh-notify-upload/install.sh 를 부른다. 사람은 sudo 비밀번호만 넣는다.
    NAS 주소는 저장소에 쓰지 않는다. ~/.ssh/config 의 별칭을 받는다.

.EXAMPLE
    .\deploy.ps1 -Host <별칭>

.EXAMPLE
    .\deploy.ps1 -Host <별칭> -Remove
#>
[CmdletBinding()]
param(
    # ~/.ssh/config 의 NAS 별칭. $Host 는 PowerShell 의 읽기 전용 자동 변수라 변수 이름은 NasHost 로 하고 -Host 로 받는다.
    [Parameter(Mandatory)][Alias('Host')][string]$NasHost,
    [switch]$Remove
)

$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$envPath = Join-Path $here 'ssh-notify.env'

if ($NasHost -notmatch '^[A-Za-z0-9._@-]+$') {
    Write-Host "별칭에는 영문·숫자·. _ @ - 만 쓴다: $NasHost"
    exit 1
}

function Test-WebhookEnv {
    # ssh-notify.env 에 견본이 아닌 https 웹훅 URL 줄이 있으면 $true. 메모장이 붙인 BOM·CRLF·따옴표를 견딘다.
    param([string]$Path)
    if (-not (Test-Path $Path)) { return $false }
    foreach ($line in Get-Content -Path $Path -Encoding UTF8) {
        if ($line.TrimStart([char]0xFEFF) -match '^\s*DISCORD_WEBHOOK_URL\s*=\s*["'']?(https://[^"''\s]+)["'']?\s*$') {
            return $Matches[1] -notmatch '[<>]'
        }
    }
    $false
}

if ($Remove) {
    $files = @('install.sh')
    $installArgs = ' --remove'
} else {
    if (-not (Test-WebhookEnv $envPath)) {
        Write-Host '웹훅 URL 이 없다. 아래 두 줄로 env 파일을 만들고 DISCORD_WEBHOOK_URL= 뒤에 웹훅 URL 을 넣는다:'
        Write-Host "  Copy-Item `"$here\ssh-notify.env.example`" `"$envPath`""
        Write-Host "  notepad `"$envPath`""
        exit 1
    }
    $files = @('ssh-notify.py', 'install.sh', 'ssh-notify.env')
    $installArgs = ''
}

foreach ($name in $files) {
    $path = Join-Path $here $name
    if (-not (Test-Path $path)) {
        Write-Host "파일이 없다: $path"
        exit 1
    }
    # CRLF 로 올라가면 NAS 의 sh·python3 가 깨진다. .gitattributes 가 LF 로 체크아웃하게 한다.
    if ($name -ne 'ssh-notify.env' -and [IO.File]::ReadAllText($path).Contains("`r")) {
        Write-Host "줄 끝이 CRLF 다: $path"
        Write-Host '  저장소 최상위에서 git add --renormalize synology 로 고친 뒤 다시 실행한다.'
        exit 1
    }
}

$ssh = (Get-Command ssh.exe).Source
$tar = (Get-Command tar.exe).Source
$tarPath = Join-Path ([IO.Path]::GetTempPath()) ("ssh-notify-upload-{0}.tar" -f [guid]::NewGuid().ToString('N'))

try {
    # 1. 올리기. PowerShell 파이프는 tar 바이트를 깨뜨리므로(5.1) 파일로 묶어 ssh 의 stdin 에 직접 쓴다.
    & $tar --format ustar -cf $tarPath -C $here @files
    if ($LASTEXITCODE -ne 0) { Write-Host "tar 로 묶지 못했다 (종료 코드 $LASTEXITCODE)."; exit 1 }

    $remote = 'rm -rf ~/ssh-notify-upload && mkdir -p ~/ssh-notify-upload && tar -xf - -C ~/ssh-notify-upload'
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $ssh
    $psi.Arguments = "$NasHost `"$remote`""
    $psi.UseShellExecute = $false
    $psi.RedirectStandardInput = $true
    $process = [Diagnostics.Process]::Start($psi)
    $stream = [IO.File]::OpenRead($tarPath)
    try {
        $stream.CopyTo($process.StandardInput.BaseStream)
    } finally {
        $stream.Dispose()
        $process.StandardInput.Close()
    }
    $process.WaitForExit()
    if ($process.ExitCode -ne 0) { Write-Host "NAS 로 올리지 못했다 (종료 코드 $($process.ExitCode))."; exit 1 }
    Write-Host "올렸다: $NasHost`:~/ssh-notify-upload/ ($($files -join ', '))"

    # 2. install.sh 부르기. 여기서 사람이 sudo 비밀번호를 넣는다.
    & $ssh -t $NasHost "sudo sh ~/ssh-notify-upload/install.sh$installArgs"
    exit $LASTEXITCODE
} finally {
    Remove-Item -LiteralPath $tarPath -Force -ErrorAction SilentlyContinue
}
