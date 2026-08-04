@echo off
setlocal
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -STA -File "%~dp0Thunder-Roulette.ps1"
endlocal
