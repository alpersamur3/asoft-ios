@echo off
rem ASoftware visionOS 27.2: build it on this PC's iOS 26 install or its base (visionos\README.md). Resumable: run it again to go on.
rem Options (-Work D:\ios26, -List, -DryRun, -From STEP, -Only STEP, -QemuDir, -AudioPlugin, -CdnEdge ...): see Install-visionOS.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install-visionOS.ps1" %*
pause
