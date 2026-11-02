@echo off
rem ASoftware iOS: install iOS 16, iOS 26 or both from this folder (the release package or the repository).
rem It asks which, and for iOS 26 whether to build with WSL or without it, shows the download, disk
rem space and time each takes on this PC, then runs installer\Install-ASoftware.ps1 (iOS 16) and
rem ios26\Install-iOS26.ps1 (iOS 26). Run it again to resume, also after a restart.
rem Options (-Version ios16, ios26 or both; -Linux wsl or helper; -Dir D:\ASoftware, -Estimate, -DryRun ...): installer\Setup-ASoftware.ps1.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0installer\Setup-ASoftware.ps1" %*
pause
