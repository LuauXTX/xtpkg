@echo off
setlocal DisableDelayedExpansion
if not defined COMSPEC (
  echo error: install.cmd requires Windows Command Prompt. 1>&2
  exit /b 1
)
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%~dp0tools\install-windows.ps1" %*
exit /b %errorlevel%
