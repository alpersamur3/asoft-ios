@echo off
rem iOS 26 in a window (GPU: host Vulkan). Set ASOFT26_WORK to the work folder, or pass -Work.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Start-iOS26.ps1" %*
