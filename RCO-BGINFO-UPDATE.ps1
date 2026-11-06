#=============================================================================
# Rowe Casa Organics  |  IT Operations Script Library
#-----------------------------------------------------------------------------
# Name        : RCO BGINFO Update
# File        : RCO-BGINFO-UPDATE.ps1  (ships inside RCO_BGINFO.zip -> C:\RCO\BGINFO)
# Platform    : Windows      Language : PowerShell   Run As : SYSTEM
# Purpose     : Draw the RCO info panel onto the RCO wallpaper for this PC.
# Author      : Kasey Tomasek
# Created     : 2026-11-06
# Source      : https://github.com/rcoktomasek/bginfo
# Sensitivity : INTERNAL -- no secrets
#=============================================================================

<#
===============================================================================
RCO BGINFO Update
Version: 2.0.3
Date: 2026-11-06
Maintainer: Kasey Tomasek
Purpose: Collect machine + connection info and draw it onto RCO_BG.bmp, saving
         C:\RCO\BGINFO\RCO_Wallpaper.bmp (the wallpaper every user gets).

Run Context:
  - Run as SYSTEM by the "\RCO\RCO BGINFO Update" scheduled task (startup,
    network change, daily) and once by RCO-BGINFO-INSTALL.ps1

Notes:
  - One image per machine, so there is no per-user line (Action1 shows who is
    signed in)
  - The panel is drawn in wallpaper pixels, centred vertically on the image, so
    it sits the same on every screen size
  - Wi-Fi line only when Wi-Fi is connected; for Wi-Fi the connection profile
    name is the SSID
  - Windows loads the new image at each user's next sign-in
  - Prints the panel text to the output (shows in Action1 via the install)
  - Logs to: %ProgramData%\RCO\Logs\BGInfo.log

Changelog:
  2.0.3 - Full computer name (was cut to 15 characters); network names without
          the " 2"/" 3" suffix Windows adds
  2.0.2 - Panel centred vertically on the screen; no "Updated" line
  2.0.1 - Log writes retry when the log is busy
  2.0.0 - Initial version (replaces Sysinternals BGInfo)
===============================================================================
#>

$ErrorActionPreference = 'Stop'

$scriptVersion = "2.0.3"
$bgDir     = "C:\RCO\BGINFO"
$bgImage   = Join-Path $bgDir "RCO_BG.bmp"
$outImage  = Join-Path $bgDir "RCO_Wallpaper.bmp"
$logPath   = Join-Path $env:ProgramData "RCO\Logs\BGInfo.log"

# Layout, in pixels of the 1920x1080 wallpaper (scaled if the image is a different size).
$panelLeft    = 1500     # left edge of the labels
$valueOffset  = 80       # labels -> values
$panelMidY    = 540      # vertical centre of the panel (middle of the screen)
$maxValueLen  = 34       # longer values are cut with "..."

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

# --- Collect -----------------------------------------------------------------

function Get-ModelName {
    param($cs)
    $mfr = switch -Regex ("$($cs.Manufacturer)") {
        '^Dell'         { 'Dell' }
        '^LENOVO'       { 'Lenovo' }
        '^(HP|Hewlett)' { 'HP' }
        '^Microsoft'    { 'Microsoft' }
        default         { "$($cs.Manufacturer)".Trim() }
    }
    $model = "$($cs.Model)".Trim()
    # Lenovo's Model is a machine-type code (20XW00...); the friendly name is in Version.
    if ($mfr -eq 'Lenovo') {
        $ver = "$((Get-CimInstance Win32_ComputerSystemProduct).Version)".Trim()
        if ($ver) { $model = $ver }
    }
    if ($model -like "$mfr*") { return $model }
    return "$mfr $model".Trim()
}

function Get-NetworkName {
    # Windows names repeat networks "RCO-Corp 2", "RCO-Corp 3"...; the profile's Description keeps
    # the original name (the SSID for Wi-Fi). Fall back to the profile name.
    param([string]$ProfileName)
    $key = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\NetworkList\Profiles'
    $match = Get-ChildItem $key -ErrorAction SilentlyContinue | Get-ItemProperty |
        Where-Object { $_.ProfileName -eq $ProfileName } | Select-Object -First 1
    if ($match -and $match.Description) { return "$($match.Description)" }
    return $ProfileName
}

function Get-Connections {
    # Connected adapters with an IPv4 default gateway, best route first.
    $cfg = @(Get-NetIPConfiguration -ErrorAction SilentlyContinue | Where-Object {
        $_.IPv4DefaultGateway -and $_.NetAdapter.Status -eq 'Up'
    } | Sort-Object { [int](@($_.IPv4DefaultGateway)[0].RouteMetric) + [int]$_.NetIPv4Interface.InterfaceMetric })
    foreach ($c in $cfg) {
        $kind = switch -Regex ("$($c.NetAdapter.PhysicalMediaType)") {
            '802\.11' { 'Wi-Fi' }
            '802\.3'  { 'Ethernet' }
            default   { 'Network' }
        }
        [pscustomobject]@{
            Kind    = $kind
            Name    = Get-NetworkName "$(@($c.NetProfile)[0].Name)"
            IP      = "$(@($c.IPv4Address)[0].IPAddress)"
            Gateway = "$(@($c.IPv4DefaultGateway)[0].NextHop)"
            MAC     = "$($c.NetAdapter.MacAddress)"
        }
    }
}

function Get-PanelLines {
    $os   = Get-CimInstance Win32_OperatingSystem
    $cs   = Get-CimInstance Win32_ComputerSystem
    $bios = Get-CimInstance Win32_BIOS
    $disk = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$($env:SystemDrive)'"
    $rel  = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction SilentlyContinue).DisplayVersion
    $osName = ("$($os.Caption)" -replace '^Microsoft\s+', '').Trim()
    if ($rel) { $osName = "$osName $rel" }

    $lines = New-Object System.Collections.Generic.List[object]
    function Add-Line { param($Kind, $Label = '', $Value = '') $lines.Add([pscustomobject]@{ Kind = $Kind; Label = $Label; Value = "$Value" }) }

    Add-Line Heading 'MACHINE INFO'
    # COMPUTERNAME is the NetBIOS name, cut to 15 characters; DNSHostName is the full name.
    $hostName = if ($cs.DNSHostName) { "$($cs.DNSHostName)".ToUpper() } else { $env:COMPUTERNAME }
    Add-Line Host '' $hostName
    Add-Line Row 'OS'     $osName
    Add-Line Row 'Model'  (Get-ModelName $cs)
    Add-Line Row 'Serial' ("$($bios.SerialNumber)".Trim())
    Add-Line Row 'RAM'    ("{0:N0} GB" -f ($cs.TotalPhysicalMemory / 1GB))
    Add-Line Row 'Disk'   ("{0} {1:N0} GB free of {2:N0} GB" -f $env:SystemDrive, ($disk.FreeSpace / 1GB), ($disk.Size / 1GB))
    Add-Line Row 'Boot'   $os.LastBootUpTime.ToString('M/d/yyyy h:mm tt')
    Add-Line Rule

    Add-Line Heading 'CONNECTION INFO'
    $conns = @(Get-Connections)
    if ($conns.Count -eq 0) {
        Add-Line Row 'Network' 'Not connected'
    } else {
        # One line per connection (Wi-Fi shows the SSID); addresses are the primary connection's.
        foreach ($c in ($conns | Select-Object -First 2)) { Add-Line Row $c.Kind $c.Name }
        Add-Line Row 'IP'      $conns[0].IP
        Add-Line Row 'Gateway' $conns[0].Gateway
        Add-Line Row 'MAC'     $conns[0].MAC
    }
    Add-Line Rule

    Add-Line Heading 'NEED IT HELP?'
    Add-Line Row 'Email'  'itsupport@rowecasaorganics.com'
    Add-Line Row 'Portal' 'it.rowecasaorganics.com'
    Add-Line Row 'Slack'  '#rco-it-support'
    Add-Line Gap
    Add-Line Heading 'EMERGENCIES ONLY'
    Add-Line Row 'Call'   '469-893-1998'
    return $lines
}

# --- Draw --------------------------------------------------------------------

function Get-LineHeight {
    param($Kind)
    switch ($Kind) {
        'Heading' { 26 }
        'Host'    { 30 }
        'Row'     { 22 }
        'Rule'    { 18 }
        'Gap'     { 10 }
        'Small'   { 18 }
    }
}

function Write-Panel {
    param($Lines)
    Add-Type -AssemblyName System.Drawing
    $bg  = [System.Drawing.Image]::FromFile($bgImage)
    $bmp = New-Object System.Drawing.Bitmap $bg.Width, $bg.Height, ([System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
    $g   = [System.Drawing.Graphics]::FromImage($bmp)
    try {
        $s = $bg.Height / 1080
        $g.DrawImage($bg, 0, 0, $bg.Width, $bg.Height)
        $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit
        $g.SmoothingMode     = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias

        $px      = [System.Drawing.GraphicsUnit]::Pixel
        $fRow    = New-Object System.Drawing.Font 'Calibri', (16 * $s), ([System.Drawing.FontStyle]::Regular), $px
        $fHead   = New-Object System.Drawing.Font 'Calibri', (15 * $s), ([System.Drawing.FontStyle]::Bold), $px
        $fHost   = New-Object System.Drawing.Font 'Calibri', (21 * $s), ([System.Drawing.FontStyle]::Bold), $px
        $fSmall  = New-Object System.Drawing.Font 'Calibri', (12 * $s), ([System.Drawing.FontStyle]::Regular), $px
        $white   = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 255, 255, 255))
        $label   = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 176, 181, 186))
        $dim     = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 130, 135, 140))
        $rulePen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(110, 255, 255, 255)), (1 * $s)
        $tf      = [System.Drawing.StringFormat]::GenericTypographic

        $total = 0; foreach ($l in $Lines) { $total += Get-LineHeight $l.Kind }
        $x  = $panelLeft * $s
        $vx = ($panelLeft + $valueOffset) * $s
        $y  = ($panelMidY * $s) - ($total * $s / 2)

        foreach ($l in $Lines) {
            $h = (Get-LineHeight $l.Kind) * $s
            $v = $l.Value
            if ($v.Length -gt $maxValueLen) { $v = $v.Substring(0, $maxValueLen - 3) + '...' }
            switch ($l.Kind) {
                'Heading' {
                    # Letter-spaced caps, like the wordmark.
                    $cx = $x
                    foreach ($ch in $l.Label.ToCharArray()) {
                        $g.DrawString([string]$ch, $fHead, $white, $cx, $y + 6 * $s, $tf)
                        $cx += $g.MeasureString([string]$ch, $fHead, 1000, $tf).Width + (2.5 * $s)
                        if ($ch -eq ' ') { $cx += 3 * $s }
                    }
                }
                'Host'  { $g.DrawString($v, $fHost, $white, $x, $y, $tf) }
                'Row'   { $g.DrawString($l.Label, $fRow, $label, $x, $y, $tf); $g.DrawString($v, $fRow, $white, $vx, $y, $tf) }
                'Rule'  { $g.DrawLine($rulePen, $x, $y + $h / 2, $x + 260 * $s, $y + $h / 2) }
                'Small' { $g.DrawString($v, $fSmall, $dim, $x, $y + 4 * $s, $tf) }
            }
            $y += $h
        }

        # Write beside the target, then swap, so nothing ever reads a half-written file.
        $tmp = "$outImage.new"
        $bmp.Save($tmp, [System.Drawing.Imaging.ImageFormat]::Bmp)
        Move-Item -Path $tmp -Destination $outImage -Force
    }
    finally {
        $g.Dispose(); $bmp.Dispose(); $bg.Dispose()
    }
}

# --- Main --------------------------------------------------------------------

try {
    $lines = Get-PanelLines
    Write-Panel $lines
    Write-Log "RCO BGINFO Update $scriptVersion drew $outImage"
    foreach ($l in $lines) {
        switch ($l.Kind) {
            'Row'     { Write-Output ("  {0,-8} {1}" -f $l.Label, $l.Value) }
            'Rule'    { Write-Output "  ------------------------" }
            'Heading' { Write-Output ("  " + $l.Label) }
            'Host'    { Write-Output ("  " + $l.Value) }
            'Small'   { Write-Output ("  " + $l.Value) }
        }
    }
    exit 0
}
catch {
    Write-Log "Update failed: $($_.Exception.Message)" -Level ERROR
    exit 1
}
