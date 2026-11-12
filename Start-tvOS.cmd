@echo off
rem ASoftware tvOS 27.2 (Apple TV 4K): tvos\Start-tvOS.ps1. -Cpus 4^|6^|8 (default 4), -NoNet, -NoFrame (the picture alone),
rem -NoQuickBoot (closing the window saves tvOS and the next start goes on from there), -PrintOnly (the QEMU command line only).
rem The keyboard is the remote: arrows move the focus, Return selects, Esc goes back (Menu); F1 the TV button, F11 full screen.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tvos\Start-tvOS.ps1" %*
if errorlevel 1 pause
