<#
.SYNOPSIS
  Patches installed Orca app.asar with randomUUID polyfill for insecure HTTP remote pairing.
#>
$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$mjsScript = Join-Path $scriptDir "patch-installed-orca.mjs"

if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
    Write-Host "[X] Node.js is not found in PATH. Please install Node.js." -ForegroundColor Red
    exit 1
}

node "$mjsScript"
