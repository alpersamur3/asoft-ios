@echo off
rem ASoftware iOS: install iOS 16, iOS 26, both, or watchOS, visionOS or tvOS (alone, without iOS 26) from this
rem folder (the release package or the repository). It asks which, and for iOS 26 whether to build with WSL or
rem without it, shows the download, disk space and time each takes on this PC, then runs installer\Install-ASoftware.ps1
rem (iOS 16), ios26\Install-iOS26.ps1 (iOS 26, or with -Base only what the others share with it),
rem watchos\Install-watchOS.ps1 (watchOS), visionos\Install-visionOS.ps1 (visionOS) and tvos\Install-tvOS.ps1 (tvOS).
rem Run it again to resume, also after a restart.
rem Options (-Version ios16, ios26, both, watchos, ios16-watchos, visionos, ios16-visionos, tvos or ios16-tvos;
rem -Watch, -Vision or -Tv yes with ios26/both; -Linux wsl or helper; -Dir D:\ASoftware, -Estimate, -DryRun ...):
rem installer\Setup-ASoftware.ps1.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0installer\Setup-ASoftware.ps1" %*
pause
