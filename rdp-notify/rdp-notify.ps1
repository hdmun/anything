<#
.SYNOPSIS
    RDP 접속 이벤트 하나를 읽어, 원격에서 온 접속이면 디스코드 웹훅으로 접속 알림을 보낸다.

.DESCRIPTION
    작업 스케줄러 작업 RdpNotify 의 이벤트 트리거가 이벤트 레코드 ID 를 넘겨 실행한다.
    용어(RDP 접속, 새 로그온, 재접속, 콘솔 접속, 출발지, 접속 알림)는 CONTEXT.md 를 따른다.

    Windows PowerShell 5.1 에서 한글이 깨지지 않도록 이 파일은 UTF-8 BOM 포함으로 저장한다.

.EXAMPLE
    .\rdp-notify.ps1 -RecordId 12345 -DryRun
    보내지 않고 메시지만 출력한다.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [long]$RecordId,

    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$LogName = 'Microsoft-Windows-TerminalServices-LocalSessionManager/Operational'
$AccessKinds = @{ 21 = '새 로그온'; 25 = '재접속' }
$EnvPath = Join-Path $PSScriptRoot 'rdp-notify.env'
$LogDir = Join-Path $PSScriptRoot 'logs'
$MaxAttempts = 3
$DefaultRetrySeconds = 5
$MaxRetrySeconds = 60

function Write-RunLog {
    # 실행 결과 한 줄을 월별 로그 파일에 남긴다. 웹훅 URL 은 절대 남기지 않는다.
    param([string]$Result, [string]$Detail)
    if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir | Out-Null }
    $path = Join-Path $LogDir ('rdp-notify-{0}.log' -f (Get-Date -Format 'yyyyMM'))
    $line = '{0} {1} rec={2} {3}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Result, $RecordId, $Detail
    Add-Content -Path $path -Value $line.TrimEnd() -Encoding UTF8
}

function Get-EventField {
    # 이벤트 XML 의 UserData/EventXML 아래 필드 값을 읽는다. 없으면 빈 문자열.
    param([xml]$Xml, [string]$Name)
    $node = $Xml.SelectSingleNode("//*[local-name()='EventXML']/*[local-name()='$Name']")
    if ($node) { $node.InnerText } else { '' }
}

function Get-AccessRecord {
    # 이벤트 레코드 하나를 판정·메시지에 필요한 값만 담은 객체로 바꾼다. 레코드가 없으면 $null.
    param([long]$Id)
    $ev = Get-WinEvent -LogName $LogName -FilterXPath "*[System[EventRecordID=$Id]]" -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if (-not $ev) { return $null }
    $xml = [xml]$ev.ToXml()
    [pscustomobject]@{
        RecordId = $ev.RecordId
        EventId  = $ev.Id
        User     = Get-EventField $xml 'User'
        Address  = Get-EventField $xml 'Address'
        Time     = $ev.TimeCreated
    }
}

function Test-RdpAccess {
    # RDP 접속(원격의 새 로그온·재접속)이면 $true. 콘솔 접속(출발지 LOCAL)과 그 밖의 이벤트는 $false.
    param([Parameter(Mandatory)] $Record)
    $AccessKinds.ContainsKey([int]$Record.EventId) -and $Record.Address -ne 'LOCAL'
}

function Format-AccessMessage {
    # 접속 알림 본문을 만든다.
    param([Parameter(Mandatory)] $Record, [string]$ComputerName = $env:COMPUTERNAME)
    $address = if ($Record.Address) { $Record.Address } else { '알 수 없음' }
    @(
        "🖥️ RDP 접속: $($AccessKinds[[int]$Record.EventId])"
        "PC: $ComputerName"
        "사용자: $($Record.User)"
        "출발지: $address"
        "시각: $($Record.Time.ToString('yyyy-MM-dd HH:mm:ss'))"
    ) -join "`n"
}

function Read-WebhookUrl {
    # rdp-notify.env 의 DISCORD_WEBHOOK_URL 값을 읽는다. 파일이나 값이 없으면 $null.
    if (-not (Test-Path $EnvPath)) { return $null }
    foreach ($line in Get-Content -Path $EnvPath -Encoding UTF8) {
        if ($line -match '^\s*DISCORD_WEBHOOK_URL\s*=\s*"?(https://\S+?)"?\s*$') { return $Matches[1] }
    }
    $null
}

function Get-RetryDelay {
    # 429 면 Retry-After(초)만큼, 그 밖의 실패는 기본값만큼 기다린다.
    param($ErrorRecord)
    $exception = $ErrorRecord.Exception
    if ($exception.PSObject.Properties['Response'] -and $exception.Response -and
        [int]$exception.Response.StatusCode -eq 429) {
        $after = 0.0
        if ([double]::TryParse([string]$exception.Response.Headers['Retry-After'], [ref]$after)) {
            return [int][Math]::Min([Math]::Ceiling($after), $MaxRetrySeconds)
        }
    }
    $DefaultRetrySeconds
}

function Send-AccessAlert {
    # 웹훅으로 접속 알림을 보낸다. 실패하면 최대 $MaxAttempts 번까지 시도한다.
    param([string]$Url, [string]$Message)
    $body = @{
        username         = 'rdp-notify'
        content          = $Message
        allowed_mentions = @{ parse = @() }
    } | ConvertTo-Json -Depth 3 -Compress
    # 5.1 은 문자열 본문을 UTF-8 로 보내지 않으므로 바이트로 넘긴다.
    $bytes = [Text.Encoding]::UTF8.GetBytes($body)
    $separator = if ($Url.Contains('?')) { '&' } else { '?' }
    $target = "$Url${separator}wait=true"
    $lastError = ''
    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        try {
            Invoke-RestMethod -Method Post -Uri $target -Body $bytes `
                -ContentType 'application/json; charset=utf-8' -TimeoutSec 15 | Out-Null
            return [pscustomobject]@{ Ok = $true; Attempts = $attempt; Error = '' }
        } catch {
            $lastError = $_.Exception.Message
            if ($attempt -lt $MaxAttempts) { Start-Sleep -Seconds (Get-RetryDelay $_) }
        }
    }
    [pscustomobject]@{ Ok = $false; Attempts = $MaxAttempts; Error = $lastError }
}

$record = Get-AccessRecord -Id $RecordId
if (-not $record) {
    Write-RunLog 'error' 'reason=event-not-found'
    Write-Host "이벤트 레코드 $RecordId 를 찾지 못했다."
    exit 1
}

$detail = 'id={0} src={1}' -f $record.EventId, $record.Address
if (-not (Test-RdpAccess $record)) {
    Write-RunLog 'skipped' $detail
    Write-Host "RDP 접속이 아니라서 건너뛴다 ($detail)."
    exit 0
}

$message = Format-AccessMessage $record
if ($DryRun) {
    Write-RunLog 'dryrun' $detail
    Write-Output $message
    exit 0
}

$url = Read-WebhookUrl
if (-not $url) {
    Write-RunLog 'error' "$detail reason=no-webhook-url"
    Write-Host "웹훅 URL 이 없다. $EnvPath 에 DISCORD_WEBHOOK_URL=https://... 를 넣는다."
    exit 1
}

$result = Send-AccessAlert -Url $url -Message $message
if ($result.Ok) {
    Write-RunLog 'sent' "$detail attempts=$($result.Attempts)"
    exit 0
}
Write-RunLog 'failed' "$detail attempts=$($result.Attempts) error=$($result.Error)"
Write-Host "접속 알림을 보내지 못했다: $($result.Error)"
exit 1
