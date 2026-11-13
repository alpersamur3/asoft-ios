@echo off
rem ASoftware tvOS 27.2: build it on this PC's iOS 26 install or its base (tvos\README.md). Resumable: run it again to go on.
rem Options (-Work D:\ios26, -List, -Estimate, -DryRun, -From STEP, -Only STEP, -QemuDir, -OtaFile, -CdnEdge, -KeepBuildFiles ...): see Install-tvOS.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install-tvOS.ps1" %*
pause
