# RCO BGInfo - Action1 script. Runs as SYSTEM.
# Downloads RCO_BGINFO.zip from GitHub to C:\RCO, expands it to C:\RCO\BGINFO (ThreatLocker-approved path)
# and sets BGInfo to run at every user's logon. Takes effect at each user's next logon.
$ErrorActionPreference = 'Stop'

$ZipUrl    = 'https://github.com/rcoktomasek/bginfo/raw/main/RCO_BGINFO.zip'
# SHA-256 of RCO_BGINFO.zip. Update this whenever the zip changes: the script refuses a zip that doesn't
# match, so a tampered or half-uploaded zip never runs as SYSTEM across the fleet.
$ZipSha256 = '78bd66f54184299a41dbcb0f289e06c5e861ee2217f43e483f027af35eae4894'
$Root      = 'C:\RCO'
$Dst       = Join-Path $Root 'BGINFO'
$OldDst    = Join-Path $Root 'RCO_BGINFO'   # earlier install location
$RunKeys   = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run',
             'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run'
$RunName   = 'RCO BGInfo'

# Download and verify.
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
New-Item $Root -ItemType Directory -Force | Out-Null
$zip = Join-Path $Root 'RCO_BGINFO.zip'
Invoke-WebRequest $ZipUrl -OutFile $zip -UseBasicParsing
$hash = (Get-FileHash $zip -Algorithm SHA256).Hash
if ($hash -ne $ZipSha256) {
    Remove-Item $zip -Force
    throw "RCO_BGINFO.zip hash $hash doesn't match the expected $ZipSha256"
}

# Expand. The zip holds a top-level BGINFO\ folder, so this lands in C:\RCO\BGINFO.
# The zip stays in C:\RCO as the local copy.
Expand-Archive $zip -DestinationPath $Root -Force
foreach ($f in 'Bginfo64.exe', 'RCO_BGINFO.bgi', 'RCO_BG.bmp') {
    if (-not (Test-Path (Join-Path $Dst $f))) { throw "Zip is missing BGINFO\$f" }
}
Write-Output "Expanded RCO_BGINFO.zip to $Dst"

# Remove older machine-wide BGInfo logon entries so it doesn't run twice.
foreach ($k in $RunKeys) {
    if (-not (Test-Path $k)) { continue }
    $key = Get-Item $k
    foreach ($n in $key.GetValueNames()) {
        if ($n -ne $RunName -and "$($key.GetValue($n))" -match 'bginfo') {
            Remove-ItemProperty $k -Name $n
            Write-Output "Removed old Run entry '$n' from $k"
        }
    }
}
$startup = Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs\StartUp'
Get-ChildItem $startup -Filter '*bginfo*' -ErrorAction SilentlyContinue | ForEach-Object {
    Remove-Item $_.FullName -Force
    Write-Output "Removed old startup shortcut $($_.Name)"
}

# Remove the earlier C:\RCO\RCO_BGINFO install; the Run entry below now points at C:\RCO\BGINFO.
if (Test-Path $OldDst) {
    Remove-Item $OldDst -Recurse -Force
    Write-Output "Removed old install folder $OldDst"
}

# Run at every user's logon.
$exe = Join-Path $Dst 'Bginfo64.exe'
$bgi = Join-Path $Dst 'RCO_BGINFO.bgi'
Set-ItemProperty $RunKeys[0] -Name $RunName -Value "`"$exe`" `"$bgi`" /timer:0 /silent /nolicprompt"
Write-Output "RCO BGInfo installed; runs at next logon"
