@echo off
setlocal EnableExtensions
cd /d "%~dp0"

echo =====================================
echo   DeckReady a1.09.2 Build + Install
echo   MSI Builder revision 10
echo =====================================
echo.

call "Build Windows MSI.bat"
if errorlevel 1 exit /b %errorlevel%

set "MSI=%CD%\release\msi\DeckReady-Windows-a1.09.2.msi"
set "LOG=%CD%\release\msi\DeckReady-Windows-a1.09.2-install.log"

if not exist "%MSI%" (
  echo ERROR: Expected MSI was not created:
  echo   %MSI%
  pause
  exit /b 1
)

echo.
echo Launching the verified installer...
echo Installer log:
echo   %LOG%
echo.
start /wait "" msiexec.exe /i "%MSI%" /L*V "%LOG%"
set "RC=%ERRORLEVEL%"

echo.
if "%RC%"=="0" (
  echo DeckReady installation completed successfully.
) else if "%RC%"=="3010" (
  echo DeckReady installation completed successfully. A restart is required.
) else (
  echo ERROR: Windows Installer exited with code %RC%.
  echo Full MSI log:
  echo   %LOG%
  echo.
  echo Last 50 error-related lines:
  powershell -NoProfile -Command "Get-Content -LiteralPath '%LOG%' ^| Select-String -Pattern 'Return value 3|error|failed' -Context 2,5 ^| Select-Object -Last 50"
)

pause
exit /b %RC%
