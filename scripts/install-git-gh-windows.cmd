@echo off
rem ---------------------------------------------------------------------------
rem Launcher for install-git-gh-windows.ps1
rem
rem Purpose: let students double-click to run without hitting the PowerShell
rem script execution policy ("running scripts is disabled on this system").
rem -ExecutionPolicy Bypass applies to this one process only; it does NOT
rem change any machine or user setting.
rem
rem IMPORTANT: this file must stay pure ASCII. cmd.exe parses batch files using
rem the console OEM code page, so non-ASCII characters here get mangled and are
rem then executed as stray commands. All Chinese user-facing text belongs in the
rem PowerShell script, which is UTF-8 with BOM and handles it correctly.
rem ---------------------------------------------------------------------------
setlocal

set "PS1=%~dp0install-git-gh-windows.ps1"

if not exist "%PS1%" (
  echo [ERROR] install-git-gh-windows.ps1 not found next to this launcher.
  echo         Please keep both files in the same folder and try again.
  pause
  exit /b 1
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%PS1%"
set "EXITCODE=%ERRORLEVEL%"

if not "%EXITCODE%"=="0" (
  echo.
  echo [INFO] Installer exited with code %EXITCODE%.
  pause
)

exit /b %EXITCODE%
