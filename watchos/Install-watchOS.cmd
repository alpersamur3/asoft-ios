@echo off
rem ASoftware watchOS 27.2 (watchos\README.md): on the base it shares with iOS 26, made first when the work
rem folder has none (about 1 GB from Apple; iOS 26 is not needed). Resumable: run it again to go on.
rem Options (-Work D:\ios26, -List, -DryRun, -From STEP, -Only STEP, -WatchIpsw, -WatchDir, -QemuFrom ...): see Install-watchOS.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install-watchOS.ps1" %*
pause
