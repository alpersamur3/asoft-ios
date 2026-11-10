@echo off
rem ASoftware iOS: install iOS 16, iOS 26, both, or watchOS (alone, without iOS 26) from this folder (the
rem release package or the repository). It asks which, and for iOS 26 whether to build with WSL or without
rem it, shows the download, disk space and time each takes on this PC, then runs installer\Install-ASoftware.ps1
rem (iOS 16), ios26\Install-iOS26.ps1 (iOS 26, or with -Base only what watchOS shares with it) and
rem watchos\Install-watchOS.ps1 (watchOS). Run it again to resume, also after a restart.
rem Options (-Version ios16, ios26, both, watchos or ios16-watchos; -Watch yes with ios26/both; -Linux wsl or helper;
rem -Dir D:\ASoftware, -Estimate, -DryRun ...): installer\Setup-ASoftware.ps1.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0installer\Setup-ASoftware.ps1" %*
pause
