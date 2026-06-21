@echo off
title AeroDrive Android Builder
color 0A

:: Set PATH locally to include Flutter and Go
set "PATH=C:\flutter\bin;C:\Program Files\Go\bin;%PATH%"

echo ==========================================
echo   AeroDrive - Android Build Script
echo ==========================================
echo.

:: Change directory to the Flutter app project
cd /d "%~dp0app"

:: 1. Check if Flutter is in PATH
call flutter --version >nul 2>&1
if %errorlevel% neq 0 (
    echo [ERROR] Flutter is not installed or not in PATH.
    pause
    exit /b 1
)

:: 2. Clean previous builds
echo [1/4] Cleaning previous builds...
call flutter clean
if %errorlevel% neq 0 (
    echo [ERROR] Flutter clean failed.
    pause
    exit /b 1
)

:: 3. Get dependencies (Offline mode if possible)
echo [2/4] Fetching dependencies...
call flutter pub get
if %errorlevel% neq 0 (
    echo [WARNING] Pub get failed. Trying offline mode...
    call flutter pub get --offline
)

:: 4. Build APK (Release mode)
echo [3/4] Building Release APK...
echo This may take a few minutes. Grab a coffee!
call flutter build apk --release --target-platform android-arm,android-arm64,android-x64

if %errorlevel% neq 0 (
    echo.
    echo [ERROR] Build failed! Check the logs above.
    pause
    exit /b 1
)

:: 5. Success message and locate file
echo.
echo [4/4] Build Successful!
echo ==========================================
echo   APK Location:
echo   %~dp0app\build\app\outputs\flutter-apk\app-release.apk
echo ==========================================
echo.

:: Optional: Open the folder containing the APK
explorer.exe "%~dp0app\build\app\outputs\flutter-apk"

pause