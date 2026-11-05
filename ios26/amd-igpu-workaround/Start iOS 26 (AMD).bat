@echo off
title ASoftware iOS 26 (AMD iGPU)
rem Applies the AMD Vulkan -13 fix (and the iGPU filter) for this window, then opens the iOS 26 menu.
rem Edit the two paths below to match your install.
set "ASOFT_APP=D:\Important\iOS\app"
set "ASOFT_CONFIG=D:\Important\iOS\ios26.config.json"
call "%~dp0ios-gpu-env.cmd"
call "%ASOFT_APP%\ios26\Start-iOS26.cmd" -Config "%ASOFT_CONFIG%"
