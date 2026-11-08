@echo off
rem ASoftware watchOS 27.2 (Apple Watch Series 9) in a drawn watch case: watchos\Start-watchOS.ps1.
rem Mouse = touch; the wheel or a drag on the crown turns it, a click presses it; the side button opens Control Center.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0watchos\Start-watchOS.ps1" %*
if errorlevel 1 pause
