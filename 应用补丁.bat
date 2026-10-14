@echo off
setlocal
set "PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
chcp 65001 >nul
"%PS%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0Bili3x.Command.ps1" -Action Apply
set "BILI_EXIT=%errorlevel%"
pause
exit /b %BILI_EXIT%
