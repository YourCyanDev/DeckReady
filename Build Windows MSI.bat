@echo off
setlocal EnableExtensions
cd /d "%~dp0"

rem DeckReady Windows a1.09.2 - MSI Builder Revision 13
rem Numeric MSI version must increase when packaging a new public release.
rem This build upgrades the previous 1.8.x and 1.9.1 installers.
set "RELEASE_LABEL=a1.09.2"
set "NUMERIC_VERSION=1.9.2"
set "Version="

set "PUBLISH_DIR=%CD%\release\win-x64"
set "MSI_DIR=%CD%\release\msi"
set "PAYLOAD_DIR=%CD%\installer\payload"
set "FINAL_MSI=%MSI_DIR%\DeckReady-Windows-%RELEASE_LABEL%.msi"

echo =====================================
echo   Building DeckReady Windows MSI
echo   Version %RELEASE_LABEL%
echo   Builder revision 12
echo =====================================
echo.

where dotnet >nul 2>nul
if errorlevel 1 (
  echo ERROR: .NET 8 SDK is not installed or is not on PATH.
  echo Install the .NET 8 SDK, then run this file again.
  pause
  exit /b 1
)

where powershell >nul 2>nul
if errorlevel 1 (
  echo ERROR: Windows PowerShell is not available.
  pause
  exit /b 1
)

rem Start clean so an older MSI cannot be mistaken for this build.
if exist "%PUBLISH_DIR%" rmdir /s /q "%PUBLISH_DIR%"
if exist "%MSI_DIR%" rmdir /s /q "%MSI_DIR%"
if exist "%PAYLOAD_DIR%" rmdir /s /q "%PAYLOAD_DIR%"
if exist "%CD%\installer\bin" rmdir /s /q "%CD%\installer\bin"
if exist "%CD%\installer\obj" rmdir /s /q "%CD%\installer\obj"

mkdir "%PUBLISH_DIR%" || goto :filesystem_failed
mkdir "%MSI_DIR%" || goto :filesystem_failed
mkdir "%PAYLOAD_DIR%" || goto :filesystem_failed

echo [1/4] Publishing the self-contained DeckReady.exe...
dotnet publish "src\DeckReady.Windows\DeckReady.Windows.csproj" ^
  -c Release ^
  -r win-x64 ^
  --self-contained true ^
  -p:PublishSingleFile=true ^
  -p:IncludeNativeLibrariesForSelfExtract=true ^
  -p:DebugType=None ^
  -p:DebugSymbols=false ^
  -o "%PUBLISH_DIR%"
if errorlevel 1 goto :publish_failed

if not exist "%PUBLISH_DIR%\DeckReady.exe" (
  echo.
  echo ERROR: dotnet publish completed but DeckReady.exe is missing:
  echo   %PUBLISH_DIR%\DeckReady.exe
  goto :failed
)

copy /y "%PUBLISH_DIR%\DeckReady.exe" "%PAYLOAD_DIR%\DeckReady.exe" >nul
if errorlevel 1 (
  echo ERROR: Could not stage DeckReady.exe for the MSI.
  goto :failed
)

echo.
echo [2/4] Restoring WiX Toolset 6 and building the MSI...
echo.
rem Never use a batch variable named VERSION here. MSBuild imports environment
rem variables as properties, and the public alpha label is not a NuGet version.
dotnet build "installer\DeckReady.Installer.wixproj" ^
  -c Release ^
  --nologo ^
  -p:Version=%NUMERIC_VERSION% ^
  -p:PackageVersion=%NUMERIC_VERSION% ^
  -p:DeckReadyReleaseLabel=%RELEASE_LABEL%
if errorlevel 1 goto :wix_failed

if not exist "%FINAL_MSI%" (
  echo.
  echo ERROR: WiX reported success but the final MSI is missing:
  echo   %FINAL_MSI%
  echo.
  echo MSI files found under installer:
  dir /s /b "%CD%\installer\*.msi" 2>nul
  goto :failed
)

for %%A in ("%FINAL_MSI%") do set "MSI_SIZE=%%~zA"
if "%MSI_SIZE%"=="0" (
  echo ERROR: The MSI exists but is zero bytes.
  goto :failed
)

echo.
echo [3/4] Verifying the cabinet is embedded inside the MSI...
rem IMPORTANT: WiX may leave an intermediate file named #cab1.cab under
rem installer\obj while producing an embedded cabinet. The leading # is the
rem Windows Installer marker for an embedded cabinet stream. Verify the final
rem MSI database itself instead of scanning temporary build files.
powershell -NoProfile -ExecutionPolicy Bypass -File "%CD%\installer\Verify-Msi.ps1" -MsiPath "%FINAL_MSI%"
if errorlevel 1 goto :cabinet_failed

echo.
echo [4/4] Verifying release outputs...
if not exist "%FINAL_MSI%" goto :failed
if not exist "%PUBLISH_DIR%\DeckReady.exe" goto :failed

echo.
echo SUCCESS
echo   EXE: %PUBLISH_DIR%\DeckReady.exe
echo   MSI: %FINAL_MSI%
echo   MSI size: %MSI_SIZE% bytes
echo   Cabinet: embedded inside MSI
echo.
echo DeckReady Windows %RELEASE_LABEL% installer build completed successfully.
start "" explorer "%MSI_DIR%"
pause
exit /b 0

:publish_failed
echo.
echo ERROR: DeckReady.exe publish failed.
echo The actual .NET compiler error is shown above.
pause
exit /b 1

:wix_failed
echo.
echo ERROR: WiX failed while compiling the MSI.
echo The actual WiX/MSBuild error is shown directly above.
pause
exit /b 1

:cabinet_failed
echo.
echo ERROR: The MSI was built, but its cabinet could not be verified as embedded.
echo Do not distribute this MSI. The verification error is shown above.
pause
exit /b 1

:filesystem_failed
echo.
echo ERROR: Could not create or clean one of DeckReady's build folders.
echo Close Explorer windows or apps using files in this folder and try again.
pause
exit /b 1

:failed
echo.
echo ERROR: DeckReady Windows MSI packaging failed.
echo This is Builder Revision 13. The exact failure is shown above.
pause
exit /b 1
