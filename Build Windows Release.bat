@echo off
setlocal EnableExtensions
cd /d "%~dp0"

echo =====================================
echo   DeckReady Windows Release Builder
echo   EXE + MSI

echo =====================================
echo.

call "Build Windows MSI.bat"
if errorlevel 1 exit /b %errorlevel%

echo.
echo DeckReady Windows a1.08.0 release outputs are ready.
pause
