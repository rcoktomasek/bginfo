#=============================================================================
# Rowe Casa Organics  |  IT Operations Script Library
#-----------------------------------------------------------------------------
# Name        : Install BGInfo WIN
# File        : RCO-Install-BGInfo-WIN.ps1  (repo: rcoktomasek/bginfo/install.ps1)
# Platform    : Windows      Language : PowerShell   Run As : SYSTEM
# Purpose     : Deploy RCO BGInfo (PC name, user, IP, last reboot, IT contact info
#               drawn on the RCO grey wallpaper) and run it at every logon.
# Author      : Kasey Tomasek
# Created     : 2026-11-06
# Source      : https://github.com/rcoktomasek/bginfo
# Sensitivity : INTERNAL -- no secrets
#=============================================================================

<#
===============================================================================
Install BGInfo WIN (Action1)
Version: 1.1.1
Date: 2026-11-06
Maintainer: Kasey Tomasek
Purpose: Download RCO_BGINFO.zip from GitHub, verify it, expand it to C:\RCO\BGINFO
         and set BGInfo to run at every user's logon.

Run Context:
  - Run as SYSTEM (Action1 default)

Notes:
  - C:\RCO is the ThreatLocker-approved path, so BGInfo runs from there
  - The zip is kept at C:\RCO\RCO_BGINFO.zip as the local copy
  - The zip's SHA-256 must match $zipSha256 or nothing is installed. Update the
    hash whenever the zip changes and commit both together (see repo README)
  - The layout (RCO_BGINFO.bgi) loads its wallpaper from C:\RCO\BGINFO\RCO_BG.bmp
  - Removes older BGInfo logon entries/shortcuts and the old C:\RCO\RCO_BGINFO
    folder so BGInfo doesn't run twice
  - Takes effect at each user's next logon; no reboot needed
  - Idempotent: safe to re-run
  - Logs to: %ProgramData%\RCO\Logs\BGInfo.log

Changelog:
  1.1.1 - Layout: panel nudged down to sit level with the RCO wordmark (1080p);
          headings in letter-spaced caps, siren emoji removed
  1.1.0 - Install to C:\RCO\BGINFO (was C:\RCO\RCO_BGINFO); keep zip in C:\RCO
        - RCO script header, logging
  1.0.0 - Initial version
===============================================================================
#>

$ErrorActionPreference = 'Stop'

$scriptVersion = "1.1.1"
$zipUrl    = "https://github.com/rcoktomasek/bginfo/raw/main/RCO_BGINFO.zip"
# SHA-256 of RCO_BGINFO.zip. The script refuses a zip that doesn't match, so a tampered or
# half-uploaded zip never runs as SYSTEM across the fleet.
$zipSha256 = "5f85ae44f73a393b475e00ed459a295160a84d98991e3b761a6c99135e5e44a0"
$rcoRoot   = "C:\RCO"
$zipPath   = Join-Path $rcoRoot "RCO_BGINFO.zip"
$bgDest    = Join-Path $rcoRoot "BGINFO"
$oldDest   = Join-Path $rcoRoot "RCO_BGINFO"   # 1.0.0 install location
$runKeys   = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run",
             "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run"
$runName   = "RCO BGInfo"
$logPath   = Join-Path $env:ProgramData "RCO\Logs\BGInfo.log"

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

try {
    Write-Log "Install BGInfo WIN $scriptVersion starting on $env:COMPUTERNAME"

    # --- Download and verify ---
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    New-Item -Path $rcoRoot -ItemType Directory -Force | Out-Null
    Invoke-WebRequest $zipUrl -OutFile $zipPath -UseBasicParsing
    $hash = (Get-FileHash $zipPath -Algorithm SHA256).Hash
    if ($hash -ne $zipSha256) {
        Remove-Item $zipPath -Force
        throw "RCO_BGINFO.zip hash $hash doesn't match the expected $zipSha256"
    }
    Write-Log "Downloaded $zipPath (SHA-256 verified)"

    # --- Expand: the zip holds a top-level BGINFO\ folder, so this lands in C:\RCO\BGINFO ---
    Expand-Archive $zipPath -DestinationPath $rcoRoot -Force
    foreach ($f in "Bginfo64.exe", "RCO_BGINFO.bgi", "RCO_BG.bmp") {
        if (-not (Test-Path (Join-Path $bgDest $f))) { throw "Zip is missing BGINFO\$f" }
    }
    Write-Log "Expanded to $bgDest"

    # --- Remove older BGInfo logon entries so it doesn't run twice ---
    foreach ($k in $runKeys) {
        if (-not (Test-Path $k)) { continue }
        $key = Get-Item $k
        foreach ($n in $key.GetValueNames()) {
            if ($n -ne $runName -and "$($key.GetValue($n))" -match "bginfo") {
                Remove-ItemProperty $k -Name $n
                Write-Log "Removed old Run entry '$n' from $k"
            }
        }
    }
    $startup = Join-Path $env:ProgramData "Microsoft\Windows\Start Menu\Programs\StartUp"
    Get-ChildItem $startup -Filter "*bginfo*" -ErrorAction SilentlyContinue | ForEach-Object {
        Remove-Item $_.FullName -Force
        Write-Log "Removed old startup shortcut $($_.Name)"
    }
    if (Test-Path $oldDest) {
        Remove-Item $oldDest -Recurse -Force
        Write-Log "Removed old install folder $oldDest"
    }

    # --- Run at every user's logon ---
    $exe = Join-Path $bgDest "Bginfo64.exe"
    $bgi = Join-Path $bgDest "RCO_BGINFO.bgi"
    Set-ItemProperty $runKeys[0] -Name $runName -Value "`"$exe`" `"$bgi`" /timer:0 /silent /nolicprompt"
    Write-Log "RCO BGInfo installed; runs at next logon"
    exit 0
}
catch {
    Write-Log "Install failed: $($_.Exception.Message)" -Level ERROR
    exit 1
}
