#=============================================================================
# Rowe Casa Organics  |  IT Operations Script Library
#-----------------------------------------------------------------------------
# Name        : RCO Logon Screen Reset
# File        : RCO-LOGONSCREEN-RESET.ps1  (repo: rcoktomasek/bginfo, LOGONSCREEN\)
# Platform    : Windows      Language : PowerShell   Run As : SYSTEM
# Purpose     : Undo RCO-LOGONSCREEN-INSTALL.ps1: Windows' own lock / sign-in
#               screen comes back and users can change it again.
# Author      : Kasey Tomasek
# Created     : 2026-11-09
# Source      : https://github.com/rcoktomasek/bginfo
# Sensitivity : INTERNAL -- no secrets
#=============================================================================

<#
===============================================================================
RCO Logon Screen Reset (Action1)
Version: 1.0.0
Date: 2026-11-09
Maintainer: Kasey Tomasek
Purpose: Remove the lock screen image setting, the clear-background setting and
         C:\RCO\LOGONSCREEN.

Run Context:
  - Run as SYSTEM (Action1 default)

Notes:
  - Takes effect from the next lock, sign-out or restart
  - Idempotent: safe to re-run
  - Logs to: %ProgramData%\RCO\Logs\LogonScreen.log

Changelog:
  1.0.0 - Initial version
===============================================================================
#>

$ErrorActionPreference = 'Stop'

$scriptVersion = "1.0.0"
$destDir   = "C:\RCO\LOGONSCREEN"
$cspKey    = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\PersonalizationCSP"
$sysPolicy = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System"
$logPath   = Join-Path $env:ProgramData "RCO\Logs\LogonScreen.log"

New-Item -Path (Split-Path $logPath) -ItemType Directory -Force | Out-Null

function Write-Log {
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet("INFO","WARN","ERROR")][string]$Level = "INFO"
    )
    $timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $entry = "[$timestamp][$Level] $Message"
    Write-Host $entry
    for ($try = 1; $try -le 10; $try++) {
        try { Add-Content -Path $logPath -Value $entry -ErrorAction Stop; break }
        catch { Start-Sleep -Milliseconds 200 }
    }
}

try {
    Write-Log "RCO Logon Screen Reset $scriptVersion starting on $env:COMPUTERNAME"

    foreach ($n in "LockScreenImagePath", "LockScreenImageUrl", "LockScreenImageStatus") {
        if ($null -ne (Get-ItemProperty $cspKey -Name $n -ErrorAction SilentlyContinue)) {
            Remove-ItemProperty $cspKey -Name $n
            Write-Log "Removed $n"
        }
    }
    if ($null -ne (Get-ItemProperty $sysPolicy -Name DisableAcrylicBackgroundOnLogon -ErrorAction SilentlyContinue)) {
        Remove-ItemProperty $sysPolicy -Name DisableAcrylicBackgroundOnLogon
        Write-Log "Removed DisableAcrylicBackgroundOnLogon"
    }
    if (Test-Path $destDir) {
        Remove-Item $destDir -Recurse -Force
        Write-Log "Removed $destDir"
    }

    Write-Log "RCO Logon Screen reset; Windows' own lock screen returns from the next lock, sign-out or restart"
    exit 0
}
catch {
    Write-Log "Reset failed: $($_.Exception.Message)" -Level ERROR
    exit 1
}
