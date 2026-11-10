@echo off
rem ASoftware visionOS 27.2 (Apple Vision Pro): visionos\Start-visionOS.ps1. -Cpus 4^|6^|8 (default 8), -Sound (the sound disk), -NoNet,
rem -NoFrame (the screen without the drawn headset), -NoQuickBoot (closing the window saves visionOS and the next start goes on from there).
rem Mouse = eyes and pinch; right button held = look around, W A S D / R F walk, Shift + W A S D turn; middle button = walk mode;
rem F1 Digital Crown (hold: recentre), F2 top button, F3/F4 volume, F9 headset on/off, F11 full screen, F12 shows the keys.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0visionos\Start-visionOS.ps1" %*
if errorlevel 1 pause
