@echo off
rem ASoftware iOS. One click: boot iOS 16 in a QEMU window, keeping what iOS writes (settings, apps) in
rem the user disk root\ios16-user.qcow2 of the work folder (ASOFT_WORK, default work\ here).
rem "Start-iOS.cmd -Reset" starts over with a new user disk.
rem In the window: side bar buttons, or F1 Home, F2 side button, F3/F4 volume; mouse = touch.
rem Closing the window saves iOS as it is (quick boot) and the next start goes on from there; Shut down in the side bar turns iOS off cleanly.
rem Apps: Install .ipa in the side bar, or drop .ipa files into ipa\ of the work folder while iOS runs (results in Installed\, Failed\).
rem Options: scripts\run-windows.ps1.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\run-windows.ps1" -Persist %*
if errorlevel 1 pause
