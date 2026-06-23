@echo off
setlocal EnableDelayedExpansion
title Build AeroDrive Android
color 0B

:: Set PATH locally
set "PATH=C:\flutter\bin;%PATH%"
set "APP_DIR=%~dp0app"

echo ==========================================
echo    AeroDrive Android Build Script
echo ==========================================
echo.

cd /d "%APP_DIR%"

echo [1/3] Fetching Flutter dependencies...
call flutter pub get
if %errorlevel% neq 0 (
    call flutter pub get --offline
)

echo.
echo [2/3] Building Android APK (Release)...
call flutter build apk --release --target-platform android-arm,android-arm64,android-x64
if %errorlevel% neq 0 (
    echo [ERROR] Android build failed!
    pause
    exit /b 1
)

echo.
echo ==========================================
echo              BUILD COMPLETE!
echo    APK Location: %APP_DIR%\build\app\outputs\flutter-apk\app-release.apk
echo ==========================================
pause
