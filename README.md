# RCO BGInfo

Shows the PC name, user, IP, last reboot and IT contact info on every RCO desktop. Deployed with Action1.

| File | What it is |
|---|---|
| `RCO_BGINFO.zip` | `RCO_BGINFO\` folder: `Bginfo64.exe`, `RCO_BGINFO.bgi` (layout), `RCO_BG.bmp` (wallpaper) |
| `install.ps1` | Action1 script (runs as SYSTEM): downloads the zip, checks its SHA-256, expands to `C:\RCO\RCO_BGINFO`, sets BGInfo to run at every logon |
| `uninstall.ps1` | Action1 script: removes the logon entry and `C:\RCO\RCO_BGINFO` |

`C:\RCO` is the ThreatLocker-approved path, so BGInfo runs from there.

## Changing the layout

1. Edit `RCO_BGINFO.bgi` in `Bginfo64.exe` on a Windows PC and save.
2. Rebuild `RCO_BGINFO.zip` with the files inside a top-level `RCO_BGINFO\` folder.
3. Get the new hash: `(Get-FileHash .\RCO_BGINFO.zip -Algorithm SHA256).Hash`
4. Put it in `$ZipSha256` in `install.ps1`, and commit the zip and `install.ps1` together.
   Until both are pushed, installs fail on the hash check instead of running a mismatched zip.
5. Re-run the Action1 script. Changes show at each user's next logon.
