@echo off
rem iOS 26 in a window (GPU: host Vulkan). The menu remembers your setup (work folder, GPU driver,
rem wallpaper, disk mode) and offers the start options every time, as the iOS 16 launcher does.
rem First run asks where the work folder is and whether you have the guest GPU driver; without one
rem iOS runs GPU-less (slower). Set ASOFT26_WORK or pass -Work to point at the work folder.
rem   Start-iOS26.cmd              the menu
rem   Start-iOS26.cmd -NoMenu      start at once with the saved setup (no menu)
rem   Start-iOS26.ps1 ...          the launcher directly (all options), bypassing the menu
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Start-iOS26-Menu.ps1" %*
if errorlevel 1 pause
