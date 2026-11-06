<#
.SYNOPSIS
    작업 스케줄러에 RdpNotify 작업을 등록·교체·제거한다. 관리자 PowerShell 에서 실행한다.

.DESCRIPTION
    RdpNotify 는 SYSTEM 계정으로, RDP 세션 이벤트(21 새 로그온, 25 재접속)가 기록될 때마다
    rdp-notify.ps1 -RecordId <그 이벤트의 레코드 ID> 를 실행한다.

    Windows PowerShell 5.1 에서 한글이 깨지지 않도록 이 파일은 UTF-8 BOM 포함으로 저장한다.

.EXAMPLE
    .\register.ps1
    등록한다. 이미 있으면 교체한다.

.EXAMPLE
    .\register.ps1 -Unregister
    작업을 지운다.

.EXAMPLE
    .\register.ps1 -PrintXml
    등록할 작업 XML 만 출력한다. 관리자 권한이 필요 없다.
#>
[CmdletBinding()]
param(
    [switch]$Unregister,
    [switch]$PrintXml
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$TaskName = 'RdpNotify'
$LogName = 'Microsoft-Windows-TerminalServices-LocalSessionManager/Operational'
$ScriptPath = Join-Path $PSScriptRoot 'rdp-notify.ps1'
$EnvPath = Join-Path $PSScriptRoot 'rdp-notify.env'

function ConvertTo-XmlText {
    param([string]$Text)
    [Security.SecurityElement]::Escape($Text)
}

function New-TaskXml {
    # 이벤트 트리거의 ValueQueries 가 이벤트 레코드 ID 를 RecordId 에 담고, 동작 인수의 $(RecordId) 로 넘긴다.
    $query = "<QueryList><Query Id=`"0`" Path=`"$LogName`"><Select Path=`"$LogName`">" +
        '*[System[(EventID=21 or EventID=25)]]</Select></Query></QueryList>'
    $arguments = "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$ScriptPath`" -RecordId `$(RecordId)"
    @"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.2" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo>
    <Description>RDP 접속(원격의 새 로그온·재접속)이 생기면 디스코드로 접속 알림을 보낸다. rdp-notify/register.ps1 이 만든다.</Description>
    <URI>\$TaskName</URI>
  </RegistrationInfo>
  <Triggers>
    <EventTrigger>
      <Enabled>true</Enabled>
      <Subscription>$(ConvertTo-XmlText $query)</Subscription>
      <ValueQueries>
        <Value name="RecordId">Event/System/EventRecordID</Value>
      </ValueQueries>
    </EventTrigger>
  </Triggers>
  <Principals>
    <Principal id="Author">
      <UserId>S-1-5-18</UserId>
      <RunLevel>HighestAvailable</RunLevel>
    </Principal>
  </Principals>
  <Settings>
    <MultipleInstancesPolicy>Parallel</MultipleInstancesPolicy>
    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
    <AllowHardTerminate>true</AllowHardTerminate>
    <StartWhenAvailable>false</StartWhenAvailable>
    <RunOnlyIfNetworkAvailable>false</RunOnlyIfNetworkAvailable>
    <IdleSettings>
      <StopOnIdleEnd>false</StopOnIdleEnd>
      <RestartOnIdle>false</RestartOnIdle>
    </IdleSettings>
    <AllowStartOnDemand>true</AllowStartOnDemand>
    <Enabled>true</Enabled>
    <Hidden>false</Hidden>
    <RunOnlyIfIdle>false</RunOnlyIfIdle>
    <WakeToRun>false</WakeToRun>
    <ExecutionTimeLimit>PT5M</ExecutionTimeLimit>
    <Priority>7</Priority>
  </Settings>
  <Actions Context="Author">
    <Exec>
      <Command>powershell.exe</Command>
      <Arguments>$(ConvertTo-XmlText $arguments)</Arguments>
    </Exec>
  </Actions>
</Task>
"@
}

function Test-Admin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    ([Security.Principal.WindowsPrincipal]$identity).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if ($PrintXml) {
    New-TaskXml
    exit 0
}

if (-not (Test-Admin)) {
    Write-Host '관리자 권한이 필요하다. PowerShell 을 "관리자 권한으로 실행"으로 연 뒤 다시 실행한다.'
    exit 1
}

if ($Unregister) {
    if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
        Write-Host "작업 $TaskName 을 지웠다."
    } else {
        Write-Host "작업 $TaskName 이 없다."
    }
    exit 0
}

if (-not (Test-Path $ScriptPath)) {
    Write-Host "알림 스크립트가 없다: $ScriptPath"
    exit 1
}

Register-ScheduledTask -TaskName $TaskName -Xml (New-TaskXml) -Force | Out-Null
Write-Host "작업 $TaskName 을 등록했다. 이제 RDP 로 새 로그온하거나 재접속하면 접속 알림이 간다."
if (-not (Test-Path $EnvPath)) {
    Write-Host "주의: $EnvPath 가 아직 없다. 만들기 전까지는 알림이 가지 않는다."
}
