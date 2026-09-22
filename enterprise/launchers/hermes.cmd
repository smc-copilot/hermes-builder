@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0hermes.ps1" %*
exit /b %ERRORLEVEL%
