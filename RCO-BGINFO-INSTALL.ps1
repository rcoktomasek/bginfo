#=============================================================================
# Rowe Casa Organics  |  IT Operations Script Library
#-----------------------------------------------------------------------------
# Name        : RCO BGINFO Install
# File        : RCO-BGINFO-INSTALL.ps1  (repo: rcoktomasek/bginfo)
# Platform    : Windows      Language : PowerShell   Run As : SYSTEM
# Purpose     : Deploy the RCO info wallpaper (machine info, connection info, IT
#               contact info on the RCO grey wallpaper) for every user on the PC,
#               enforced by policy so users can't change it.
# Author      : Kasey Tomasek
# Created     : 2026-11-06
# Source      : https://github.com/rcoktomasek/bginfo
# Sensitivity : INTERNAL -- no secrets
#=============================================================================

<#
===============================================================================
RCO BGINFO Install (Action1)
Version: 2.0.5
Date: 2026-11-09
Maintainer: Kasey Tomasek
Purpose: One-shot install. Download RCO_BGINFO.zip from GitHub, verify it, expand
         it to C:\RCO\BGINFO, draw the wallpaper, enforce it for every user by
         policy, and keep it current with a SYSTEM scheduled task.

Run Context:
  - Run as SYSTEM (Action1 default)
  - Undo with RCO-BGINFO-RESET.ps1 (removes the policy; users get their own
    wallpaper back and can change it again)

Notes:
  - C:\RCO is the ThreatLocker-approved path
  - The zip is kept at C:\RCO\RCO_BGINFO.zip as the local copy
  - The zip's SHA-256 must match $zipSha256 or nothing is installed. Update the
    hash whenever the zip changes and commit both together (see repo README)
  - C:\RCO\BGINFO is read-only for users (the task runs its script as SYSTEM)
  - Wallpaper policy (the "Desktop Wallpaper" + "Prevent changing desktop
    background" Group Policy settings, Fill) in every local profile and the
    Default profile, so new users get it too. Users' own wallpaper setting is
    not touched, so RCO-BGINFO-RESET.ps1 puts it back as it was. Settings shows
    "Some settings are managed by your organization". Users can't remove the
    policy without admin rights. Takes effect at each user's next sign-in
  - Task "\RCO\RCO BGINFO Update" redraws the image at startup, at sign-in,
    on network change and daily at 06:00
  - Removes BGInfo 1.x (HKLM Run entry, C:\RCO\RCO_BGINFO, old files)
  - Idempotent: safe to re-run
  - Logs to: %ProgramData%\RCO\Logs\BGInfo.log

Changelog:
  2.0.5 - Download retried 3 times; skipped when the local zip already matches
          (runs daily from the "RCO BGINFO - Ensure (daily)" Action1 automation)
  2.0.4 - Fix: a locked user hive (reg load error) stopped the script; it now warns and moves on
  2.0.3 - Full computer name (was cut to 15 characters); network names without
          the " 2"/" 3" suffix Windows adds
  2.0.2 - Panel centred vertically on the screen; no "Updated" line
  2.0.1 - Fix: install failed when it and the update script wrote the log at once
  2.0.0 - SYSTEM-drawn wallpaper (RCO-BGINFO-UPDATE.ps1) replaces Sysinternals
          BGInfo; Machine Info / Connection Info / Need IT Help sections; wallpaper
          enforced by policy for all users; scheduled task; renamed
          RCO-BGINFO-INSTALL.ps1
  1.1.1 - Layout: panel level with the wordmark; letter-spaced headings
  1.1.0 - Install to C:\RCO\BGINFO; keep zip in C:\RCO; RCO header, logging
  1.0.0 - Initial version (install.ps1)
===============================================================================
#>

$ErrorActionPreference = 'Stop'

$scriptVersion = "2.0.5"
$zipUrl    = "https://github.com/rcoktomasek/bginfo/raw/main/RCO_BGINFO.zip"
# SHA-256 of RCO_BGINFO.zip. The script refuses a zip that doesn't match, so a tampered or
# half-uploaded zip never runs as SYSTEM across the fleet.
$zipSha256 = "12d1c27c726af341d688f77ba8825ef8f59930ccfcd75f983e311455042d405e"
$rcoRoot   = "C:\RCO"
$zipPath   = Join-Path $rcoRoot "RCO_BGINFO.zip"
$bgDest    = Join-Path $rcoRoot "BGINFO"
$updater   = Join-Path $bgDest "RCO-BGINFO-UPDATE.ps1"
$wallpaper = Join-Path $bgDest "RCO_Wallpaper.bmp"
$taskPath  = "\RCO\"
$taskName  = "RCO BGINFO Update"
$runKeys   = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run",
             "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run"
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

# Task: redraw the image as SYSTEM. No window (runs in session 0).
$taskXml = @"
<Task version="1.2" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo>
    <Author>Rowe Casa Organics IT</Author>
    <Description>Redraws the RCO info wallpaper (C:\RCO\BGINFO\RCO_Wallpaper.bmp). Installed by RCO-BGINFO-INSTALL.ps1 $scriptVersion.</Description>
  </RegistrationInfo>
  <Triggers>
    <BootTrigger><Enabled>true</Enabled><Delay>PT1M</Delay></BootTrigger>
    <LogonTrigger><Enabled>true</Enabled></LogonTrigger>
    <CalendarTrigger>
      <StartBoundary>2026-01-01T06:00:00</StartBoundary>
      <Enabled>true</Enabled>
      <ScheduleByDay><DaysInterval>1</DaysInterval></ScheduleByDay>
    </CalendarTrigger>
    <EventTrigger>
      <Enabled>true</Enabled>
      <Delay>PT30S</Delay>
      <Subscription>&lt;QueryList&gt;&lt;Query Id="0" Path="Microsoft-Windows-NetworkProfile/Operational"&gt;&lt;Select Path="Microsoft-Windows-NetworkProfile/Operational"&gt;*[System[(EventID=10000 or EventID=10001)]]&lt;/Select&gt;&lt;/Query&gt;&lt;/QueryList&gt;</Subscription>
    </EventTrigger>
  </Triggers>
  <Principals>
    <Principal id="System">
      <UserId>S-1-5-18</UserId>
      <RunLevel>HighestAvailable</RunLevel>
    </Principal>
  </Principals>
  <Settings>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
    <StartWhenAvailable>true</StartWhenAvailable>
    <ExecutionTimeLimit>PT5M</ExecutionTimeLimit>
    <Enabled>true</Enabled>
  </Settings>
  <Actions Context="System">
    <Exec>
      <Command>powershell.exe</Command>
      <Arguments>-NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File "$updater"</Arguments>
    </Exec>
  </Actions>
</Task>
"@

try {
    Write-Log "RCO BGINFO Install $scriptVersion starting on $env:COMPUTERNAME"

    # --- Download and verify ---
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    New-Item -Path $rcoRoot -ItemType Directory -Force | Out-Null
    # The daily re-run skips the download when the local zip is already the right one.
    if ((Test-Path $zipPath) -and (Get-FileHash $zipPath -Algorithm SHA256).Hash -eq $zipSha256) {
        Write-Log "$zipPath is current (SHA-256 verified); no download needed"
    } else {
        # Three tries: one DNS blip or a laptop dropping Wi-Fi shouldn't fail the install.
        for ($try = 1; $try -le 3; $try++) {
            try { Invoke-WebRequest $zipUrl -OutFile $zipPath -UseBasicParsing -TimeoutSec 120; break }
            catch {
                if ($try -eq 3) { throw }
                Write-Log "Download attempt $try failed ($($_.Exception.Message)); retrying in 30s" "WARN"
                Start-Sleep -Seconds 30
            }
        }
        $hash = (Get-FileHash $zipPath -Algorithm SHA256).Hash
        if ($hash -ne $zipSha256) {
            Remove-Item $zipPath -Force
            throw "RCO_BGINFO.zip hash $hash doesn't match the expected $zipSha256"
        }
        Write-Log "Downloaded $zipPath (SHA-256 verified)"
    }

    # --- Remove BGInfo 1.x: logon entries, old folder, old files in C:\RCO\BGINFO ---
    foreach ($k in $runKeys) {
        if (-not (Test-Path $k)) { continue }
        $key = Get-Item $k
        foreach ($n in $key.GetValueNames()) {
            if ("$($key.GetValue($n))" -match "bginfo") {
                Remove-ItemProperty $k -Name $n
                Write-Log "Removed Run entry '$n' from $k"
            }
        }
    }
    $startup = Join-Path $env:ProgramData "Microsoft\Windows\Start Menu\Programs\StartUp"
    Get-ChildItem $startup -Filter "*bginfo*" -ErrorAction SilentlyContinue | ForEach-Object {
        Remove-Item $_.FullName -Force
        Write-Log "Removed old startup shortcut $($_.Name)"
    }
    foreach ($old in (Join-Path $rcoRoot "RCO_BGINFO"), (Join-Path $bgDest "Bginfo.exe"), (Join-Path $bgDest "Bginfo64.exe"),
                     (Join-Path $bgDest "RCO_BGINFO.bgi"), (Join-Path $bgDest "RCO_BGInfo")) {
        if (Test-Path $old) {
            Remove-Item $old -Recurse -Force
            Write-Log "Removed old $old"
        }
    }

    # --- Expand: the zip holds a top-level BGINFO\ folder, so this lands in C:\RCO\BGINFO ---
    Expand-Archive $zipPath -DestinationPath $rcoRoot -Force
    foreach ($f in "RCO_BG.bmp", "RCO-BGINFO-UPDATE.ps1") {
        if (-not (Test-Path (Join-Path $bgDest $f))) { throw "Zip is missing BGINFO\$f" }
    }
    Write-Log "Expanded to $bgDest"

    # --- Lock the folder: SYSTEM + Administrators full, Users read/execute only ---
    & icacls.exe $bgDest /inheritance:r /grant:r "*S-1-5-18:(OI)(CI)F" "*S-1-5-32-544:(OI)(CI)F" "*S-1-5-32-545:(OI)(CI)RX" /Q | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "icacls failed on $bgDest (exit $LASTEXITCODE)" }
    Write-Log "Set $bgDest to read-only for users"

    # --- Draw the wallpaper now (prints the panel text) ---
    # Collect the output first: the updater writes the same log, so log its lines after it exits.
    $updOut  = @(& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $updater 2>&1)
    $updCode = $LASTEXITCODE
    $updOut | Where-Object { "$_" -notmatch '^\[\d{4}-' } | ForEach-Object { Write-Log "$_" }
    if ($updCode -ne 0 -or -not (Test-Path $wallpaper)) { throw "RCO-BGINFO-UPDATE.ps1 didn't draw $wallpaper (exit $updCode): $($updOut -join ' | ')" }
    Write-Log "Drew $wallpaper"

    # --- Scheduled task ---
    Register-ScheduledTask -TaskPath $taskPath -TaskName $taskName -Xml $taskXml -Force | Out-Null
    Write-Log "Registered scheduled task $taskPath$taskName"

    # --- Wallpaper policy for every profile (Fill = "4" in the policy's numbering) ---
    Invoke-ForEachUserHive {
        param($root, $name)
        $sys = "$root\Software\Microsoft\Windows\CurrentVersion\Policies\System"
        $ad  = "$root\Software\Microsoft\Windows\CurrentVersion\Policies\ActiveDesktop"
        foreach ($k in $sys, $ad) { if (-not (Test-Path $k)) { New-Item $k -Force | Out-Null } }
        Set-ItemProperty $sys -Name Wallpaper          -Value $wallpaper -Type String
        Set-ItemProperty $sys -Name WallpaperStyle     -Value "4"        -Type String
        Set-ItemProperty $ad  -Name NoChangingWallPaper -Value 1         -Type DWord
        Write-Log "Applied wallpaper policy for $name"
    }

    Write-Log "RCO BGINFO $scriptVersion installed; users see it at next sign-in"
    exit 0
}
catch {
    Write-Log "Install failed: $($_.Exception.Message)" -Level ERROR
    exit 1
}
