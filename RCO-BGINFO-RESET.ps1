#=============================================================================
# Rowe Casa Organics  |  IT Operations Script Library
#-----------------------------------------------------------------------------
# Name        : RCO BGINFO Reset
# File        : RCO-BGINFO-RESET.ps1  (repo: rcoktomasek/bginfo)
# Platform    : Windows      Language : PowerShell   Run As : SYSTEM
# Purpose     : Remove the RCO wallpaper policy so every user gets their own
#               wallpaper back and can change it again.
# Author      : Kasey Tomasek
# Created     : 2026-11-06
# Source      : https://github.com/rcoktomasek/bginfo
# Sensitivity : INTERNAL -- no secrets
#=============================================================================

<#
===============================================================================
RCO BGINFO Reset (Action1)
Version: 2.0.4
Date: 2026-11-06
Maintainer: Kasey Tomasek
Purpose: Undo the wallpaper policy applied by RCO-BGINFO-INSTALL.ps1.

Run Context:
  - Run as SYSTEM (Action1 default)

Notes:
  - Removes the Wallpaper / WallpaperStyle / NoChangingWallPaper policy values
    from every local profile and the Default profile
  - Each user's own wallpaper setting was never changed, so it comes back as it
    was. Exception: if it points into C:\RCO\BGINFO (set by BGInfo 1.x) it is
    reset to the Windows default, since that file is gone
  - Leaves C:\RCO\BGINFO and the "\RCO\RCO BGINFO Update" task in place; re-run
    RCO-BGINFO-INSTALL.ps1 to turn the policy back on
  - Takes effect at each user's next sign-in
  - Logs to: %ProgramData%\RCO\Logs\BGInfo.log

Changelog:
  2.0.4 - Fix: a locked user hive (reg load error) stopped the script; it now warns and moves on
  2.0.1 - Log writes retry when the log is busy
  2.0.0 - Initial version
===============================================================================
#>

$ErrorActionPreference = 'Stop'

$scriptVersion = "2.0.4"
$winDefault    = Join-Path $env:WINDIR "Web\Wallpaper\Windows\img0.jpg"
$logPath       = Join-Path $env:ProgramData "RCO\Logs\BGInfo.log"

New-Item -Path (Split-Path $logPath) -ItemType Directory -Force | Out-Null

function Write-Log {
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet("INFO","WARN","ERROR")][string]$Level = "INFO"
    )
    $timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $entry = "[$timestamp][$Level] $Message"
    Write-Host $entry
    # The task and the install can log at the same moment: retry briefly, never fail on a log line.
    for ($try = 1; $try -le 10; $try++) {
        try { Add-Content -Path $logPath -Value $entry -ErrorAction Stop; break }
        catch { Start-Sleep -Milliseconds 200 }
    }
}

function Invoke-ForEachUserHive {
    # Runs $Action once per user registry hive: every local profile (loading the hive if the
    # user isn't signed in) plus the Default profile, so new users get the same settings.
    param([Parameter(Mandatory)][scriptblock]$Action)
    $targets = @(Get-CimInstance Win32_UserProfile | Where-Object { -not $_.Special -and $_.LocalPath } |
        ForEach-Object { [pscustomobject]@{ Name = $_.SID; Dat = Join-Path $_.LocalPath 'NTUSER.DAT' } })
    $targets += [pscustomobject]@{ Name = 'Default'; Dat = Join-Path $env:SystemDrive 'Users\Default\NTUSER.DAT' }
    foreach ($t in $targets) {
        $root   = "Registry::HKEY_USERS\$($t.Name)"
        $loaded = $false
        if (-not (Test-Path $root)) {
            if (-not (Test-Path $t.Dat)) { continue }
            $root = "Registry::HKEY_USERS\RCO_$($t.Name)"
            # cmd does the redirect: in PowerShell 5.1, 2>&1 on a native command throws under Stop.
            cmd.exe /c "reg.exe load `"HKU\RCO_$($t.Name)`" `"$($t.Dat)`" >nul 2>&1"
            if ($LASTEXITCODE -ne 0) { Write-Log "Couldn't load the hive for $($t.Name)" -Level WARN; continue }
            $loaded = $true
        }
        try { & $Action $root $t.Name }
        catch { Write-Log "$($t.Name): $($_.Exception.Message)" -Level WARN }
        finally {
            if ($loaded) {
                [gc]::Collect(); [gc]::WaitForPendingFinalizers()
                cmd.exe /c "reg.exe unload `"HKU\RCO_$($t.Name)`" >nul 2>&1"
                if ($LASTEXITCODE -ne 0) { Write-Log "Couldn't unload the hive for $($t.Name)" -Level WARN }
            }
        }
    }
}

try {
    Write-Log "RCO BGINFO Reset $scriptVersion starting on $env:COMPUTERNAME"
    Invoke-ForEachUserHive {
        param($root, $name)
        $sys  = "$root\Software\Microsoft\Windows\CurrentVersion\Policies\System"
        $ad   = "$root\Software\Microsoft\Windows\CurrentVersion\Policies\ActiveDesktop"
        $desk = "$root\Control Panel\Desktop"
        foreach ($v in @(@($sys, 'Wallpaper'), @($sys, 'WallpaperStyle'), @($ad, 'NoChangingWallPaper'))) {
            Remove-ItemProperty -Path $v[0] -Name $v[1] -ErrorAction SilentlyContinue
        }
        $own = (Get-ItemProperty $desk -ErrorAction SilentlyContinue).Wallpaper
        if ("$own" -like "C:\RCO\BGINFO\*") {
            Set-ItemProperty $desk -Name Wallpaper -Value $winDefault -Type String
            Write-Log "Removed wallpaper policy for $name (own wallpaper was a BGInfo 1.x file; set to the Windows default)"
        } else {
            Write-Log "Removed wallpaper policy for $name"
        }
    }
    Write-Log "RCO BGINFO policy removed; users get their own wallpaper back at next sign-in"
    exit 0
}
catch {
    Write-Log "Reset failed: $($_.Exception.Message)" -Level ERROR
    exit 1
}
