# RCO BGInfo - Action1 uninstall script. Runs as SYSTEM.
# The current wallpaper image stays until the user changes it.
$ErrorActionPreference = 'Continue'

Remove-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run' -Name 'RCO BGInfo' -ErrorAction SilentlyContinue
Remove-Item 'C:\RCO\BGINFO', 'C:\RCO\RCO_BGINFO', 'C:\RCO\RCO_BGINFO.zip' -Recurse -Force -ErrorAction SilentlyContinue

Write-Output 'RCO BGInfo removed'
