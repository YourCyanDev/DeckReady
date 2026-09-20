@echo off
setlocal
cd /d "%~dp0"

echo =====================================
echo   Building DeckReady Windows EXE
echo =====================================
echo.

where dotnet >nul 2>nul
if errorlevel 1 (
  echo ERROR: .NET 8 SDK is not installed or is not on PATH.
  pause
  exit /b 1
)

if exist "release\win-x64" rmdir /s /q "release\win-x64"

dotnet publish "src\DeckReady.Windows\DeckReady.Windows.csproj" ^
  -c Release ^
  -r win-x64 ^
  --self-contained true ^
  -p:PublishSingleFile=true ^
  -p:IncludeNativeLibrariesForSelfExtract=true ^
  -p:DebugType=None ^
  -p:DebugSymbols=false ^
  -o "release\win-x64"

if errorlevel 1 goto :failed

echo.
echo SUCCESS
echo DeckReady.exe is in:
echo   %CD%\release\win-x64
echo.
start "" explorer "%CD%\release\win-x64"
pause
exit /b 0

:failed
echo.
echo Build failed. Copy the error above and send it back for a patch.
pause
exit /b 1
