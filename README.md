# RCO BGINFO

Puts machine info, connection info and IT contact info on the RCO grey wallpaper for every user
on a Windows PC, and stops users changing it. Deployed with Action1, run as SYSTEM.

| Script | What it does |
|---|---|
| `RCO-BGINFO-INSTALL.ps1` | One-shot install. Downloads `RCO_BGINFO.zip`, checks its SHA-256, expands to `C:\RCO\BGINFO` (read-only for users), draws `RCO_Wallpaper.bmp`, enforces it for every profile (and new users) with the Desktop Wallpaper / Prevent changing desktop background policies, and registers the `\RCO\RCO BGINFO Update` task. Removes BGInfo 1.x. |
| `RCO-BGINFO-RESET.ps1` | Removes the wallpaper policy. Users get their own wallpaper back and can change it again. |
| `RCO-BGINFO-VERIFY.ps1` | Checks an install (files, folder permissions, task, policy per profile, drawn image) and prints PASS/FAIL plus JPEG previews. Use on each test PC. |
| `RCO-BGINFO-UPDATE.ps1` | Ships inside the zip. Draws the panel onto `RCO_BG.bmp`. Run as SYSTEM by the task at startup, sign-in, network change and daily 06:00. |

Changes show at each user's next sign-in. All scripts log to `%ProgramData%\RCO\Logs\BGInfo.log`.
`C:\RCO` is the ThreatLocker-approved path.

## Panel

Machine Info (name, OS + release, model, serial, RAM, disk, last boot), Connection Info
(Ethernet / Wi-Fi SSID, IP, gateway, MAC), Need IT Help (email, portal, Slack, emergency line),
centred vertically on the screen. Layout values are at the top of `RCO-BGINFO-UPDATE.ps1`.

## Changing the panel or wallpaper

1. Edit `RCO-BGINFO-UPDATE.ps1` (and/or `RCO_BG.bmp`, 1920x1080).
2. Rebuild `RCO_BGINFO.zip` with both files inside a top-level `BGINFO\` folder.
3. Get the new hash: `(Get-FileHash .\RCO_BGINFO.zip -Algorithm SHA256).Hash`
4. Put it in `$zipSha256` in `RCO-BGINFO-INSTALL.ps1`, bump the versions and changelogs, and commit
   the zip and scripts together. Until both are pushed, installs fail on the hash check.
5. Re-run `RCO-BGINFO-INSTALL.ps1` from Action1.
