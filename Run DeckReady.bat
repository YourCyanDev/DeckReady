@echo off
setlocal
cd /d "%~dp0"

echo =====================================
echo   DeckReady for Windows - Alpha a1.09.2
echo =====================================
echo.

where dotnet >nul 2>nul
if errorlevel 1 (
  echo ERROR: .NET 8 SDK is not installed or is not on PATH.
  echo Install the .NET 8 SDK, then run this file again.
  pause
  exit /b 1
)

echo Restoring packages...
dotnet restore "src\DeckReady.Windows\DeckReady.Windows.csproj"
if errorlevel 1 goto :failed

echo.
echo Starting DeckReady...
dotnet run --project "src\DeckReady.Windows\DeckReady.Windows.csproj"
exit /b %errorlevel%

:failed
echo.
echo DeckReady could not restore/build. Copy the error above and send it back for a patch.
pause
exit /b 1
