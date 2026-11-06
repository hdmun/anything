# $PROFILE 에서 dot-source 한다:  . "$env:USERPROFILE\scripts\agent-accounts\AgentAccounts.ps1"
# accounts.psd1 의 계정마다 <cli>-<계정> 별칭(함수)을 만든다.

$global:AgentAccountsConfigPath = Join-Path $PSScriptRoot 'accounts.psd1'
$global:AgentAccountsRoot = Join-Path $HOME '.agent-accounts'

function Resolve-AgentPath([string]$Path) {
    if ($Path.StartsWith('~')) { $Path = Join-Path $HOME $Path.Substring(1).TrimStart('/', '\') }
    return $Path
}

function Read-AgentConfig {
    if (-not (Test-Path $global:AgentAccountsConfigPath)) {
        $example = Join-Path $PSScriptRoot 'accounts.example.psd1'
        Copy-Item $example $global:AgentAccountsConfigPath
    }
    Import-PowerShellDataFile $global:AgentAccountsConfigPath
}

function Get-AgentAccountDir([string]$Cli, [string]$Name) {
    Join-Path (Join-Path $global:AgentAccountsRoot $Cli) $Name
}

function Register-AgentAlias([string]$Cli, [string]$Name, [string]$EnvName) {
    $dir = Get-AgentAccountDir $Cli $Name
    $body = @"
`$exe = Get-Command '$Cli' -CommandType Application, ExternalScript -ErrorAction Stop | Select-Object -First 1
`$old = [Environment]::GetEnvironmentVariable('$EnvName', 'Process')
[Environment]::SetEnvironmentVariable('$EnvName', '$dir', 'Process')
try { & `$exe.Source @args } finally { [Environment]::SetEnvironmentVariable('$EnvName', `$old, 'Process') }
"@
    Set-Item -Path "function:global:$Cli-$Name" -Value ([scriptblock]::Create($body))
}

function Write-AgentConfig($Config) {
    $q = { param($s) "'" + ($s -replace "'", "''") + "'" }
    $lines = @('@{', '    Clis = @{')
    foreach ($cli in $Config.Clis.Keys | Sort-Object) {
        $c = $Config.Clis[$cli]
        $share = ($c.Share | ForEach-Object { & $q $_ }) -join ', '
        $seed = ($c.Seed.Keys | ForEach-Object { "$(& $q $_) = $(& $q $c.Seed[$_])" }) -join '; '
        $lines += "        $cli = @{"
        $lines += "            Env       = $(& $q $c.Env)"
        $lines += "            Default   = $(& $q $c.Default)"
        $lines += "            Share     = @($share)"
        $lines += "            LoginFile = $(& $q $c.LoginFile)"
        $lines += "            Seed      = @{ $seed }"
        $lines += '        }'
    }
    $lines += '    }', '    Accounts = @{'
    foreach ($cli in $Config.Accounts.Keys | Sort-Object) {
        $names = ($Config.Accounts[$cli] | ForEach-Object { & $q $_ }) -join ', '
        $lines += "        $cli = @($names)"
    }
    $lines += '    }', '}'
    Set-Content -Path $global:AgentAccountsConfigPath -Value $lines -Encoding utf8
}

function Add-AgentAccount {
    <#
    .SYNOPSIS
    새 계정 폴더를 만들고, 공유 항목을 링크하고, accounts.psd1 에 등록한다.
    .EXAMPLE
    Add-AgentAccount claude sub   # 이후 claude-sub 실행 → 첫 실행에서 로그인
    #>
    param(
        [Parameter(Mandatory)][string]$Cli,
        [Parameter(Mandatory)][ValidatePattern('^[A-Za-z0-9_]+$')][string]$Name
    )
    $config = Read-AgentConfig
    $def = $config.Clis[$Cli]
    if (-not $def) { throw "accounts.psd1 에 '$Cli' CLI 정의가 없다. 있는 것: $($config.Clis.Keys -join ', ')" }

    $dir = Get-AgentAccountDir $Cli $Name
    New-Item -ItemType Directory -Force -Path $dir | Out-Null

    $src = Resolve-AgentPath $def.Default
    foreach ($item in $def.Share) {
        $from = Join-Path $src $item
        $to = Join-Path $dir $item
        if (-not (Test-Path $from)) { Write-Warning "공유 원본 없음, 건너뜀: $from"; continue }
        if (Test-Path $to) { continue }
        if ((Get-Item $from).PSIsContainer) {
            New-Item -ItemType Junction -Path $to -Target $from | Out-Null
        } else {
            New-Item -ItemType SymbolicLink -Path $to -Target $from | Out-Null
        }
    }
    foreach ($file in $def.Seed.Keys) {
        $p = Join-Path $dir $file
        if (-not (Test-Path $p)) { Set-Content -Path $p -Value $def.Seed[$file] -Encoding utf8 }
    }

    $accounts = @{}
    foreach ($k in $config.Accounts.Keys) { $accounts[$k] = @($config.Accounts[$k]) }
    if ($accounts[$Cli] -notcontains $Name) { $accounts[$Cli] = @($accounts[$Cli]) + $Name }
    $config = @{ Clis = $config.Clis; Accounts = $accounts }
    Write-AgentConfig $config

    Register-AgentAlias $Cli $Name $def.Env
    Write-Host "준비됨: $Cli-$Name  (폴더: $dir). 실행해서 로그인한다."
}

function Get-AgentAccount {
    <#
    .SYNOPSIS
    계정마다 폴더·공유 링크·로그인 상태를 보여 준다.
    #>
    $config = Read-AgentConfig
    foreach ($cli in $config.Accounts.Keys | Sort-Object) {
        $def = $config.Clis[$cli]
        foreach ($name in $config.Accounts[$cli]) {
            $dir = Get-AgentAccountDir $cli $name
            $broken = @($def.Share | Where-Object {
                $p = Join-Path $dir $_
                (Test-Path (Join-Path (Resolve-AgentPath $def.Default) $_)) -and -not (Test-Path $p)
            })
            [pscustomobject]@{
                Alias    = "$cli-$name"
                Folder   = (Test-Path $dir)
                LoggedIn = (Test-Path (Join-Path $dir $def.LoginFile))
                Missing  = $broken -join ', '
                Path     = $dir
            }
        }
    }
}

# 프로필 로드 시 별칭 등록
& {
    $config = Read-AgentConfig
    foreach ($cli in $config.Accounts.Keys) {
        foreach ($name in $config.Accounts[$cli]) {
            Register-AgentAlias $cli $name $config.Clis[$cli].Env
        }
    }
}
