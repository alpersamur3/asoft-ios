@echo off
rem ASoftware iOS 26: build iOS 26 on this PC and set it up (README.md, Build). Resumable: run it again to go on.
rem Options (-Work D:\ios26, -List, -Check, -DryRun, -From STEP, -Only STEP, -Collections, -QemuFrom ...): see Install-iOS26.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install-iOS26.ps1" %*
pause
