@echo off
setlocal EnableDelayedExpansion
title Build AeroDrive Windows
color 0B

:: Set PATH locally
set "PATH=C:\flutter\bin;%PATH%"

set "TDLIB_DLL_SRC=%~dp0tdlib\tdjson.dll"
set "APP_DIR=%~dp0app"

echo ==========================================
echo    AeroDrive Windows Build Script
echo ==========================================
echo.

:: Check and enable Developer Mode (required for symlinks by Flutter plugins)
echo [0/3] Checking Developer Mode...
for /f "tokens=3" %%a in ('reg query "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock" /v AllowDevelopmentWithoutDevLicense 2^>nul') do set "DEVMODE=%%a"

if not "%DEVMODE%"=="0x1" (
    echo - Developer Mode is OFF. Attempting to enable...
    reg add "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock" /t REG_DWORD /f /v "AllowDevelopmentWithoutDevLicense" /d 1 >nul 2>&1
    if %errorlevel% neq 0 (
        echo.
        echo ==============================================================
        echo [ERROR] Could not enable Developer Mode automatically.
        echo.
        echo Flutter requires Developer Mode for symlink support.
        echo Please do ONE of the following:
        echo.
        echo 1. Right-click this batch file and "Run as Administrator"
        echo    OR
        echo 2. Enable Developer Mode manually:
        echo    Settings ^(Win+I^) -^> System -^> For developers -^> ON
        echo ==============================================================
        echo.
        pause
        exit /b 1
    )
    echo - Developer Mode enabled successfully!
)

cd /d "%APP_DIR%"

echo.
echo [1/3] Fetching Flutter dependencies...
call flutter pub get
if %errorlevel% neq 0 (
    call flutter pub get --offline
)

echo.
echo [2/3] Building Windows Executable (Release)...
call flutter build windows --release
if %errorlevel% neq 0 (
    echo.
    echo [ERROR] Windows build failed!
    pause
    exit /b 1
)

:: Copy tdjson.dll
set "WIN_RELEASE_DIR=%APP_DIR%\build\windows\x64\runner\Release"
if exist "%TDLIB_DLL_SRC%" (
    echo - Injecting tdjson.dll into Release bundle...
    copy /Y "%TDLIB_DLL_SRC%" "%WIN_RELEASE_DIR%\tdjson.dll" >nul
) else (
    echo [WARNING] tdjson.dll not found at %TDLIB_DLL_SRC%. You must place it manually.
)

:: Create Portable Zip using PowerShell
echo - Zipping Portable Windows Release...
powershell -Command "Compress-Archive -Path '%WIN_RELEASE_DIR%\*' -DestinationPath '%~dp0AeroDrive_Windows_Portable.zip' -Force"

:: Create Installer if Inno Setup is installed
echo - Checking for Inno Setup (ISCC)...
where iscc >nul 2>&1
if %errorlevel% equ 0 (
    echo - Compiling Windows Installer ^(Setup.exe^)...
    iscc "%APP_DIR%\aerodrive_setup.iss"
    echo - Installer Location: %APP_DIR%\Output\AeroDrive_Setup.exe
)

echo.
echo ==========================================
echo              BUILD COMPLETE!
echo    Portable Zip: AeroDrive_Windows_Portable.zip
echo ==========================================
pause
