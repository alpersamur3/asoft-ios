@echo off
rem ASoftware watchOS 27.2: build it on this PC's iOS 26 install (watchos\README.md). Resumable: run it again to go on.
rem Options (-Work D:\ios26, -List, -DryRun, -From STEP, -Only STEP, -WatchIpsw, -WatchDir, -QemuFrom ...): see Install-watchOS.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install-watchOS.ps1" %*
pause
