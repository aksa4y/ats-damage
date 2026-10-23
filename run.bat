@echo off
setlocal
chcp 65001 >nul
cd /d "%~dp0"
if not exist "%~dp0scripts\run.ps1" (
  echo ERROR: Extract the entire repository first. scripts\run.ps1 is missing.
  pause
  exit /b 1
)
set "PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if exist "%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe" set "PS=%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe"
"%PS%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\run.ps1" %*
set "RESULT=%ERRORLEVEL%"
if not "%RESULT%"=="0" echo Installation did not complete. See the message above and .setup\logs.
pause
exit /b %RESULT%
