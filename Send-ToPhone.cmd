@echo off
rem ASoftware iOS: send the iOS 16 this PC installed to the Android app (scripts\Send-ToPhone.ps1).
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Send-ToPhone.ps1" %*
if errorlevel 1 pause
