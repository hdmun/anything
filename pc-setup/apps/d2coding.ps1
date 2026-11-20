[CmdletBinding()]
param([switch]$Check)

$script:D2CodingFontValueName = 'D2Coding & D2Coding Bold & D2Coding ligature & D2Coding ligature Bold (TrueType)'

function Get-D2CodingFontPaths {
    $regPath = 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Fonts'
    if (-not (Test-Path -LiteralPath $regPath)) {
        return @()
    }
    $props = Get-ItemProperty -LiteralPath $regPath -ErrorAction SilentlyContinue
    if ($null -eq $props) {
        return @()
    }
    $paths = [System.Collections.Generic.List[string]]::new()
    foreach ($p in $props.PSObject.Properties) {
        if ($p.Name -like 'D2Coding*' -and -not [string]::IsNullOrWhiteSpace([string]$p.Value)) {
            $paths.Add([Environment]::ExpandEnvironmentVariables([string]$p.Value))
        }
    }
    return @($paths)
}

function Test-FileExists {
    param([Parameter(Mandatory)][string]$Path)
    return (Test-Path -LiteralPath $Path -PathType Leaf)
}

function Test-D2CodingInstalled {
    $fontPaths = @(Get-D2CodingFontPaths)
    foreach ($fp in $fontPaths) {
        if (Test-FileExists -Path $fp) {
            return $true
        }
    }
    return $false
}

function Get-D2CodingLatestRelease {
    $resp = Invoke-WebRequest -Uri 'https://api.github.com/repos/naver/d2-coding-font/releases/latest' -UseBasicParsing
    return ($resp.Content | ConvertFrom-Json)
}

function Invoke-FileDownload {
    param(
        [Parameter(Mandatory)][string]$Uri,
        [Parameter(Mandatory)][string]$OutFile
    )
    Invoke-WebRequest -Uri $Uri -OutFile $OutFile -UseBasicParsing
}

function Copy-FontFile {
    param(
        [Parameter(Mandatory)][string]$SourcePath,
        [Parameter(Mandatory)][string]$DestinationPath
    )
    $destDir = Split-Path -Parent $DestinationPath
    if (-not (Test-Path -LiteralPath $destDir)) {
        New-Item -ItemType Directory -Path $destDir -Force | Out-Null
    }
    Copy-Item -LiteralPath $SourcePath -Destination $DestinationPath -Force
}

function Set-D2CodingFontRegistry {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Value
    )
    $regPath = 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Fonts'
    if (-not (Test-Path -LiteralPath $regPath)) {
        New-Item -Path $regPath -Force | Out-Null
    }
    Set-ItemProperty -LiteralPath $regPath -Name $Name -Value $Value -Type String
}

function Invoke-Main {
    param([switch]$Check)

    if (Test-D2CodingInstalled) {
        Write-Output '그대로'
        return
    }

    if ($Check) {
        Write-Output '다름 (설치 안 됨)'
        return
    }

    $release = Get-D2CodingLatestRelease
    $asset = $null
    if ($null -ne $release -and $null -ne $release.assets) {
        $asset = $release.assets | Where-Object { $_.name -like 'D2Coding-Ver*.zip' } | Select-Object -First 1
    }
    if ($null -eq $asset -or [string]::IsNullOrWhiteSpace([string]$asset.browser_download_url)) {
        Write-Output '실패: D2Coding 릴리스 자산을 찾지 못했다'
        return
    }

    $tempDir = Join-Path $env:TEMP ("d2coding-" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
    try {
        $zipPath = Join-Path $tempDir $asset.name
        $extractDir = Join-Path $tempDir 'extracted'

        Write-Host "D2Coding 내려받기 중: $($asset.browser_download_url)"
        Invoke-FileDownload -Uri $asset.browser_download_url -OutFile $zipPath

        Expand-Archive -LiteralPath $zipPath -DestinationPath $extractDir -Force

        $allDir = Join-Path $extractDir 'D2CodingAll'
        $ttcFile = $null
        if (Test-Path -LiteralPath $allDir -PathType Container) {
            $ttcFile = Get-ChildItem -LiteralPath $allDir -Filter '*-all.ttc' -File -ErrorAction SilentlyContinue | Select-Object -First 1
        }
        if ($null -eq $ttcFile) {
            Write-Output '실패: D2Coding all.ttc 가 없다'
            return
        }

        $fontsDir = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Fonts'
        $destPath = Join-Path $fontsDir $ttcFile.Name

        Write-Host "D2Coding 폰트 설치 중: $destPath"
        Copy-FontFile -SourcePath $ttcFile.FullName -DestinationPath $destPath
        Set-D2CodingFontRegistry -Name $script:D2CodingFontValueName -Value $destPath

        Write-Output '바꿈'
    } finally {
        if (Test-Path -LiteralPath $tempDir) {
            Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    Invoke-Main -Check:$Check
}
