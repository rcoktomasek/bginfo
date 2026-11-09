#=============================================================================
# Rowe Casa Organics  |  IT Operations Script Library
#-----------------------------------------------------------------------------
# Name        : RCO Logon Screen Install
# File        : RCO-LOGONSCREEN-INSTALL.ps1  (repo: rcoktomasek/bginfo, LOGONSCREEN\)
# Platform    : Windows      Language : PowerShell   Run As : SYSTEM
# Purpose     : Set the RCO lock / sign-in screen image (RCO branding plus the
#               "owned and managed by Rowe Casa Organics" notice) for the whole PC.
# Author      : Kasey Tomasek
# Created     : 2026-11-09
# Source      : https://github.com/rcoktomasek/bginfo
# Sensitivity : INTERNAL -- no secrets
#=============================================================================

<#
===============================================================================
RCO Logon Screen Install (Action1)
Version: 1.0.0
Date: 2026-11-09
Maintainer: Kasey Tomasek
Purpose: One-shot install. Download RCO_Logon.jpg from GitHub, verify it, copy it to
         C:\RCO\LOGONSCREEN, and make it the lock and sign-in screen image.

Run Context:
  - Run as SYSTEM (Action1 default)
  - Undo with RCO-LOGONSCREEN-RESET.ps1

Notes:
  - Display only: nothing to click, so automatic sign-in still works (this is not
    the "Interactive logon: message" legal notice, which always needs an OK)
  - Doesn't touch credential providers, so GCPW (Google sign-in) and Windows
    sign-in work the same with or without it
  - Lock screen image: HKLM PersonalizationCSP LockScreenImagePath/Url/Status
    (Windows Pro has no Group Policy for this). Users can't change it in Settings
  - "Show clear logon background" (DisableAcrylicBackgroundOnLogon=1) so the
    notice isn't blurred behind the sign-in box
  - The image's SHA-256 must match $imageSha256 or nothing is changed
  - Shows from the next lock / sign-out / restart
  - Idempotent: safe to re-run
  - Logs to: %ProgramData%\RCO\Logs\LogonScreen.log

Changelog:
  1.0.0 - Initial version
===============================================================================
#>

$ErrorActionPreference = 'Stop'

$scriptVersion = "1.0.0"
$imageUrl    = "https://github.com/rcoktomasek/bginfo/raw/main/LOGONSCREEN/RCO_Logon.jpg"
# SHA-256 of RCO_Logon.jpg. Update it whenever the image changes and commit both together.
$imageSha256 = "a92c23f8cf84ba6c1e7cb22224f8571af0e50e3e729ee4e51fcd24e1b5f91902"
$destDir     = "C:\RCO\LOGONSCREEN"
$image       = Join-Path $destDir "RCO_Logon.jpg"
$cspKey      = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\PersonalizationCSP"
$sysPolicy   = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System"
$logPath     = Join-Path $env:ProgramData "RCO\Logs\LogonScreen.log"

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
    Write-Log "RCO Logon Screen Install $scriptVersion starting on $env:COMPUTERNAME"

    # --- Download and verify (skipped when the local copy already matches) ---
    New-Item -Path $destDir -ItemType Directory -Force | Out-Null
    if ((Test-Path $image) -and (Get-FileHash $image -Algorithm SHA256).Hash -eq $imageSha256) {
        Write-Log "$image is current (SHA-256 verified); no download needed"
    } else {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $tmp = "$image.download"
        for ($try = 1; $try -le 3; $try++) {
            try { Invoke-WebRequest $imageUrl -OutFile $tmp -UseBasicParsing -TimeoutSec 120; break }
            catch {
                if ($try -eq 3) { throw }
                Write-Log "Download attempt $try failed ($($_.Exception.Message)); retrying in 30s" -Level WARN
                Start-Sleep -Seconds 30
            }
        }
        $hash = (Get-FileHash $tmp -Algorithm SHA256).Hash
        if ($hash -ne $imageSha256) {
            Remove-Item $tmp -Force
            throw "RCO_Logon.jpg hash $hash doesn't match the expected $imageSha256"
        }
        Move-Item $tmp $image -Force
        Write-Log "Downloaded $image (SHA-256 verified)"
    }

    # --- Lock the folder: SYSTEM + Administrators full, Users read/execute only ---
    & icacls.exe $destDir /inheritance:r /grant:r "*S-1-5-18:(OI)(CI)F" "*S-1-5-32-544:(OI)(CI)F" "*S-1-5-32-545:(OI)(CI)RX" /Q | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "icacls failed on $destDir (exit $LASTEXITCODE)" }
    Write-Log "Set $destDir to read-only for users"

    # --- Lock / sign-in screen image ---
    if (-not (Test-Path $cspKey)) { New-Item $cspKey -Force | Out-Null }
    Set-ItemProperty $cspKey -Name LockScreenImagePath   -Value $image -Type String
    Set-ItemProperty $cspKey -Name LockScreenImageUrl    -Value $image -Type String
    Set-ItemProperty $cspKey -Name LockScreenImageStatus -Value 1      -Type DWord
    Write-Log "Set lock screen image to $image"

    # --- Clear (unblurred) background behind the sign-in box ---
    if (-not (Test-Path $sysPolicy)) { New-Item $sysPolicy -Force | Out-Null }
    Set-ItemProperty $sysPolicy -Name DisableAcrylicBackgroundOnLogon -Value 1 -Type DWord
    Write-Log "Enabled 'Show clear logon background'"

    # A plain-colour sign-in screen would hide the image; report it, don't change it.
    if ((Get-ItemProperty $sysPolicy -ErrorAction SilentlyContinue).DisableLogonBackgroundImage -eq 1) {
        Write-Log "DisableLogonBackgroundImage=1 is set: the sign-in screen will be a plain colour (lock screen still shows the image)" -Level WARN
    }

    Write-Log "RCO Logon Screen $scriptVersion installed; shows from the next lock, sign-out or restart"
    exit 0
}
catch {
    Write-Log "Install failed: $($_.Exception.Message)" -Level ERROR
    exit 1
}
