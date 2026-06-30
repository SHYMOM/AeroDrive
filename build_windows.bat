@echo off
setlocal EnableDelayedExpansion
title Build AeroDrive Windows
color 0B

echo ==========================================
echo    AeroDrive Windows Build Script
echo ==========================================
echo.

:: --- Locate Flutter binary path directly ---
set "FLUTTER="

where flutter 2>nul >nul
if %errorlevel% equ 0 (
    for /f "delims=" %%a in ('where flutter') do (
        if not defined FLUTTER set "FLUTTER=%%a"
    )
)

if not defined FLUTTER (
    if defined FLUTTER_ROOT (
        if exist "!FLUTTER_ROOT!\bin\flutter.bat" set "FLUTTER=!FLUTTER_ROOT!\bin\flutter.bat"
        if exist "!FLUTTER_ROOT!\bin\flutter.exe" set "FLUTTER=!FLUTTER_ROOT!\bin\flutter.exe"
    )
)

if not defined FLUTTER (
    for %%p in ("%USERPROFILE%\flutter" "%LOCALAPPDATA%\flutter" "C:\flutter" "C:\tools\flutter" "C:\src\flutter") do (
        if exist "%%~p\bin\flutter.bat" set "FLUTTER=%%~p\bin\flutter.bat"
        if exist "%%~p\bin\flutter.exe" set "FLUTTER=%%~p\bin\flutter.exe"
    )
)

if not defined FLUTTER (
    echo [ERROR] Flutter not found! Install from https://flutter.dev/docs/get-started/install
    pause
    exit /b 1
)

echo - Found Flutter: !FLUTTER!
echo.

set "TDLIB_DLL_SRC=%~dp0tdlib\tdjson.dll"
set "APP_DIR=%~dp0app"

:: Check and enable Developer Mode (required for symlinks by Flutter plugins)
echo [0/3] Checking Developer Mode...
for /f "tokens=3" %%a in ('reg query "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock" /v AllowDevelopmentWithoutDevLicense 2^>nul') do set "DEVMODE=%%a"

if not "!DEVMODE!"=="0x1" (
    echo - Developer Mode is OFF. Attempting to enable...
    reg add "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock" /t REG_DWORD /f /v "AllowDevelopmentWithoutDevLicense" /d 1 >nul 2>&1
    if !errorlevel! neq 0 (
        echo.
        echo ==============================================================
        echo [ERROR] Could not enable Developer Mode automatically.
        echo.
        echo Please run this script as Administrator, or
        echo enable Developer Mode manually:
        echo    Settings ^(Win+I^) -^> System -^> For developers -^> ON
        echo ==============================================================
        pause
        exit /b 1
    )
    echo - Developer Mode enabled successfully!
)

cd /d "!APP_DIR!"

echo.
echo [1/3] Fetching Flutter dependencies...
call "!FLUTTER!" pub get
if !errorlevel! neq 0 (
    call "!FLUTTER!" pub get --offline
)

echo.
echo [2/3] Building Windows Executable (Release)...
call "!FLUTTER!" build windows --release
if !errorlevel! neq 0 (
    echo [ERROR] Windows build failed!
    pause
    exit /b 1
)

:: Copy tdjson.dll
set "WIN_RELEASE_DIR=!APP_DIR!\build\windows\x64\runner\Release"
if exist "!TDLIB_DLL_SRC!" (
    echo - Injecting tdjson.dll into Release bundle...
    copy /Y "!TDLIB_DLL_SRC!" "!WIN_RELEASE_DIR!\tdjson.dll" >nul
) else (
    echo [WARNING] tdjson.dll not found at !TDLIB_DLL_SRC!.
)

:: Create Portable Zip
echo - Zipping Portable Windows Release...
powershell -Command "Compress-Archive -Path '!WIN_RELEASE_DIR!\*' -DestinationPath '%~dp0AeroDrive_Windows_Portable.zip' -Force"

:: Create Installer if Inno Setup is installed
echo - Checking for Inno Setup (ISCC)...
where iscc >nul 2>&1
if !errorlevel! equ 0 (
    echo - Compiling Windows Installer...
    iscc "!APP_DIR!\aerodrive_setup.iss"
    echo - Installer: !APP_DIR!\Output\AeroDrive_Setup.exe
) else (
    echo - Inno Setup not found. Skipping installer.
    echo - Download from: https://jrsoftware.org/isdl.php
)

echo.
echo ==========================================
echo              BUILD COMPLETE!
echo    Portable Zip: AeroDrive_Windows_Portable.zip
echo ==========================================
pause
