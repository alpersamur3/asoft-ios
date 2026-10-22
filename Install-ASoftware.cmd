@echo off
rem ASoftware iOS: install it from this folder (the release package): our QEMU, Python, iOS 16.7.16
rem from Apple, the iOS disk and its first start, about an hour in all. Run it again to resume.
rem Options (e.g. -Dir D:\ASoftware): installer\Install-ASoftware.ps1.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0installer\Install-ASoftware.ps1" %*
pause
