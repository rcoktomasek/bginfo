#=============================================================================
# Rowe Casa Organics  |  IT Operations Script Library
#-----------------------------------------------------------------------------
# Name        : Uninstall BGInfo WIN
# File        : RCO-Uninstall-BGInfo-WIN.ps1  (repo: rcoktomasek/bginfo/uninstall.ps1)
# Platform    : Windows      Language : PowerShell   Run As : SYSTEM
# Purpose     : Remove RCO BGInfo: logon entry, C:\RCO\BGINFO and the local zip.
# Author      : Kasey Tomasek
# Created     : 2026-11-06
# Source      : https://github.com/rcoktomasek/bginfo
# Sensitivity : INTERNAL -- no secrets
#=============================================================================

<#
===============================================================================
Uninstall BGInfo WIN (Action1)
Version: 1.1.0
Date: 2026-11-06
Maintainer: Kasey Tomasek
Purpose: Undo Install BGInfo WIN.

Run Context:
  - Run as SYSTEM (Action1 default)

Notes:
  - Removes C:\RCO\BGINFO, the old C:\RCO\RCO_BGINFO and C:\RCO\RCO_BGINFO.zip
  - The current wallpaper image stays until the user changes it or Windows resets it
  - Logs to: %ProgramData%\RCO\Logs\BGInfo.log

Changelog:
  1.1.0 - Remove C:\RCO\BGINFO and the zip; RCO script header, logging
  1.0.0 - Initial version
===============================================================================
#>

$ErrorActionPreference = 'Continue'

$scriptVersion = "1.1.0"
$runKey  = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"
$runName = "RCO BGInfo"
$paths   = "C:\RCO\BGINFO", "C:\RCO\RCO_BGINFO", "C:\RCO\RCO_BGINFO.zip"
$logPath = Join-Path $env:ProgramData "RCO\Logs\BGInfo.log"

New-Item -Path (Split-Path $logPath) -ItemType Directory -Force | Out-Null

function Write-Log {
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet("INFO","WARN","ERROR")][string]$Level = "INFO"
    )
    $timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $entry = "[$timestamp][$Level] $Message"
    Write-Host $entry
    Add-Content -Path $logPath -Value $entry
}

Write-Log "Uninstall BGInfo WIN $scriptVersion starting on $env:COMPUTERNAME"
Remove-ItemProperty $runKey -Name $runName -ErrorAction SilentlyContinue
foreach ($p in $paths) {
    if (Test-Path $p) {
        Remove-Item $p -Recurse -Force
        Write-Log "Removed $p"
    }
}
Write-Log "RCO BGInfo removed"
