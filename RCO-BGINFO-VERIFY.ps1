#=============================================================================
# Rowe Casa Organics  |  IT Operations Script Library
#-----------------------------------------------------------------------------
# Name        : RCO BGINFO Verify
# File        : RCO-BGINFO-VERIFY.ps1  (repo: rcoktomasek/bginfo)
# Platform    : Windows      Language : PowerShell   Run As : SYSTEM
# Purpose     : Check that RCO-BGINFO-INSTALL.ps1 worked on this PC: files,
#               permissions, task, wallpaper policy per profile, drawn image.
# Author      : Kasey Tomasek
# Created     : 2026-11-06
# Source      : https://github.com/rcoktomasek/bginfo
# Sensitivity : INTERNAL -- no secrets
#=============================================================================

<#
===============================================================================
RCO BGINFO Verify (Action1)
Version: 2.0.4
Date: 2026-11-06
Maintainer: Kasey Tomasek
Purpose: Prove an install on a test PC before rolling out further.

Run Context:
  - Run as SYSTEM (Action1 default)

Notes:
  - Read-only, except it starts the "\RCO\RCO BGINFO Update" task once to prove
    the task redraws the image (same thing the task does daily)
  - Prints PASS / FAIL per check, then JPEG previews of the drawn wallpaper as
    base64 between BEGIN/END markers (whole image at 640 px, and the panel at
    full size) so the result can be looked at without remoting in
  - Exit code 1 if any check fails

Changelog:
  2.0.4 - Fix: a locked user hive (reg load error) stopped the script; it now warns and moves on
  2.0.0 - Initial version
===============================================================================
#>

$ErrorActionPreference = 'Stop'

$scriptVersion = "2.0.4"
$bgDir     = "C:\RCO\BGINFO"
$wallpaper = Join-Path $bgDir "RCO_Wallpaper.bmp"
$zipPath   = "C:\RCO\RCO_BGINFO.zip"
$installer = "https://github.com/rcoktomasek/bginfo/raw/main/RCO-BGINFO-INSTALL.ps1"
$taskPath  = "\RCO\"
$taskName  = "RCO BGINFO Update"
$logPath   = Join-Path $env:ProgramData "RCO\Logs\BGInfo.log"
$script:failed = 0

function Test-Check {
    param([string]$Name, [bool]$Ok, [string]$Detail = '')
    $tag = if ($Ok) { 'PASS' } else { $script:failed++; 'FAIL' }
    Write-Output ("[{0}] {1}{2}" -f $tag, $Name, $(if ($Detail) { " -- $Detail" } else { '' }))
}

function Invoke-ForEachUserHive {
    # Runs $Action once per user registry hive: every local profile (loading the hive if the
    # user isn't signed in) plus the Default profile.
    param([Parameter(Mandatory)][scriptblock]$Action)
    $targets = @(Get-CimInstance Win32_UserProfile | Where-Object { -not $_.Special -and $_.LocalPath } |
        ForEach-Object { [pscustomobject]@{ Name = $_.SID; Path = $_.LocalPath; Dat = Join-Path $_.LocalPath 'NTUSER.DAT' } })
    $targets += [pscustomobject]@{ Name = 'Default'; Path = 'Default profile'; Dat = Join-Path $env:SystemDrive 'Users\Default\NTUSER.DAT' }
    foreach ($t in $targets) {
        $root   = "Registry::HKEY_USERS\$($t.Name)"
        $loaded = $false
        if (-not (Test-Path $root)) {
            if (-not (Test-Path $t.Dat)) { continue }
            $root = "Registry::HKEY_USERS\RCO_$($t.Name)"
            # cmd does the redirect: in PowerShell 5.1, 2>&1 on a native command throws under Stop.
            cmd.exe /c "reg.exe load `"HKU\RCO_$($t.Name)`" `"$($t.Dat)`" >nul 2>&1"
            if ($LASTEXITCODE -ne 0) { Test-Check "Policy $($t.Path)" $false "couldn't load hive"; continue }
            $loaded = $true
        }
        try { & $Action $root $t }
        finally {
            if ($loaded) {
                [gc]::Collect(); [gc]::WaitForPendingFinalizers()
                cmd.exe /c "reg.exe unload `"HKU\RCO_$($t.Name)`" >nul 2>&1"
            }
        }
    }
}

function Write-Preview {
    param([string]$Label, [System.Drawing.Image]$Image, [System.Drawing.Rectangle]$Crop, [int]$Width)
    $h   = [int]($Crop.Height * $Width / $Crop.Width)
    $out = New-Object System.Drawing.Bitmap $Width, $h
    $g   = [System.Drawing.Graphics]::FromImage($out)
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.DrawImage($Image, (New-Object System.Drawing.Rectangle 0, 0, $Width, $h), $Crop, [System.Drawing.GraphicsUnit]::Pixel)
    $enc = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object MimeType -eq 'image/jpeg'
    $ep  = New-Object System.Drawing.Imaging.EncoderParameters 1
    $ep.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter ([System.Drawing.Imaging.Encoder]::Quality), ([long]80)
    $ms  = New-Object System.IO.MemoryStream
    $out.Save($ms, $enc, $ep)
    $g.Dispose(); $out.Dispose()
    $b64 = [Convert]::ToBase64String($ms.ToArray())
    Write-Output "BEGIN-PREVIEW $Label"
    for ($i = 0; $i -lt $b64.Length; $i += 1000) { Write-Output $b64.Substring($i, [Math]::Min(1000, $b64.Length - $i)) }
    Write-Output "END-PREVIEW $Label"
}

Write-Output "RCO BGINFO Verify $scriptVersion on $env:COMPUTERNAME at $((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))"

# --- Files and zip hash ---
foreach ($f in "RCO_BG.bmp", "RCO-BGINFO-UPDATE.ps1", "RCO_Wallpaper.bmp") {
    $p = Join-Path $bgDir $f
    Test-Check "File $p" (Test-Path $p) $(if (Test-Path $p) { "{0:N0} bytes, {1}" -f (Get-Item $p).Length, (Get-Item $p).LastWriteTime } else { 'missing' })
}
try {
    $expected = ([regex]'\$zipSha256 = "([0-9a-f]{64})"').Match((Invoke-WebRequest $installer -UseBasicParsing).Content).Groups[1].Value
    $actual   = (Get-FileHash $zipPath -Algorithm SHA256).Hash
    Test-Check "Zip matches GitHub install script" ($expected -and $actual -eq $expected) "local $actual"
} catch { Test-Check "Zip matches GitHub install script" $false $_.Exception.Message }

# --- Old BGInfo gone ---
$runHits = foreach ($k in "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run", "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run") {
    if (Test-Path $k) { $key = Get-Item $k; $key.GetValueNames() | Where-Object { "$($key.GetValue($_))" -match 'bginfo' } }
}
Test-Check "No BGInfo Run entries" (-not $runHits) ($runHits -join ', ')
$oldFiles = @("C:\RCO\RCO_BGINFO", "$bgDir\Bginfo.exe", "$bgDir\Bginfo64.exe", "$bgDir\RCO_BGINFO.bgi") | Where-Object { Test-Path $_ }
Test-Check "No BGInfo 1.x files" (-not $oldFiles) ($oldFiles -join ', ')

# --- Folder permissions: users can read, not write ---
$acl  = Get-Acl $bgDir
$aces = $acl.Access | ForEach-Object {
    $sid = try { $_.IdentityReference.Translate([System.Security.Principal.SecurityIdentifier]).Value } catch { "$($_.IdentityReference)" }
    [pscustomobject]@{ Sid = $sid; Name = "$($_.IdentityReference)"; Rights = "$($_.FileSystemRights)"; Type = "$($_.AccessControlType)" }
}
$writers = $aces | Where-Object { $_.Type -eq 'Allow' -and $_.Sid -notin 'S-1-5-18', 'S-1-5-32-544' -and $_.Rights -match 'Write|Modify|FullControl|CreateFiles|AppendData|Delete' }
Test-Check "Only SYSTEM/Administrators can write $bgDir" (-not $writers) (($aces | ForEach-Object { "$($_.Name)=$($_.Rights)" }) -join '; ')
Test-Check "Users can read $bgDir" ([bool]($aces | Where-Object { $_.Sid -eq 'S-1-5-32-545' -and $_.Rights -match 'ReadAndExecute|Read' }))

# --- Scheduled task (and prove it redraws) ---
$task = Get-ScheduledTask -TaskPath $taskPath -TaskName $taskName -ErrorAction SilentlyContinue
Test-Check "Task $taskPath$taskName exists" ([bool]$task)
if ($task) {
    Test-Check "Task runs as SYSTEM" ($task.Principal.UserId -match 'SYSTEM|S-1-5-18') "$($task.Principal.UserId)"
    Test-Check "Task enabled with 4 triggers" ($task.State -ne 'Disabled' -and @($task.Triggers).Count -eq 4) "$($task.State), $(@($task.Triggers).Count) triggers"
    $before = (Get-Item $wallpaper -ErrorAction SilentlyContinue).LastWriteTime
    Start-ScheduledTask -TaskPath $taskPath -TaskName $taskName
    $deadline = (Get-Date).AddSeconds(90)
    do { Start-Sleep -Seconds 3; $state = (Get-ScheduledTask -TaskPath $taskPath -TaskName $taskName).State } while ($state -eq 'Running' -and (Get-Date) -lt $deadline)
    $info  = Get-ScheduledTaskInfo -TaskPath $taskPath -TaskName $taskName
    $after = (Get-Item $wallpaper -ErrorAction SilentlyContinue).LastWriteTime
    Test-Check "Task run succeeded and redrew the image" ($info.LastTaskResult -eq 0 -and $after -gt $before) "result $($info.LastTaskResult), image $before -> $after"
}

# --- Wallpaper policy in every profile ---
Invoke-ForEachUserHive {
    param($root, $t)
    $sys = Get-ItemProperty "$root\Software\Microsoft\Windows\CurrentVersion\Policies\System" -ErrorAction SilentlyContinue
    $ad  = Get-ItemProperty "$root\Software\Microsoft\Windows\CurrentVersion\Policies\ActiveDesktop" -ErrorAction SilentlyContinue
    $own = (Get-ItemProperty "$root\Control Panel\Desktop" -ErrorAction SilentlyContinue).Wallpaper
    $ok  = $sys.Wallpaper -eq $wallpaper -and "$($sys.WallpaperStyle)" -eq '4' -and $ad.NoChangingWallPaper -eq 1
    Test-Check "Policy $($t.Path)" $ok ("Wallpaper=$($sys.Wallpaper) Style=$($sys.WallpaperStyle) NoChanging=$($ad.NoChangingWallPaper) (own: $own)")
}

# --- Drawn image ---
Add-Type -AssemblyName System.Drawing
if (Test-Path $wallpaper) {
    $bytes = [IO.File]::ReadAllBytes($wallpaper)
    $img   = [System.Drawing.Image]::FromStream((New-Object System.IO.MemoryStream (,$bytes)))
    Test-Check "Image is 1920x1080" ($img.Width -eq 1920 -and $img.Height -eq 1080) "$($img.Width)x$($img.Height)"
    Write-Preview 'full'  $img (New-Object System.Drawing.Rectangle 0, 0, $img.Width, $img.Height) 640
    Write-Preview 'panel' $img (New-Object System.Drawing.Rectangle 1440, 250, 480, 660) 480
    $img.Dispose()
}

Write-Output "--- last 15 log lines ($logPath) ---"
Get-Content $logPath -Tail 15 -ErrorAction SilentlyContinue
Write-Output ("RESULT: {0}" -f $(if ($script:failed) { "$($script:failed) check(s) FAILED" } else { 'ALL CHECKS PASSED' }))
exit [int]($script:failed -gt 0)
