@echo off
setlocal EnableDelayedExpansion
title Build AeroDrive Android
color 0B

echo ==========================================
echo    AeroDrive Android Build Script
echo ==========================================
echo.

:: --- Locate Flutter ---
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
    echo [ERROR] Flutter not found! Install from: https://flutter.dev/docs/get-started/install
    pause
    exit /b 1
)

echo - Found Flutter: !FLUTTER!
echo.

:: --- Auto-add Windows Defender exclusion for gen_snapshot.EXE ---
:: gen_snapshot.EXE is a legitimate Flutter tool often blocked by Windows Application Control.
set "ENGINE_DIR=C:\flutter\bin\cache\artifacts\engine"
if exist "!ENGINE_DIR!" (
    powershell -Command "& {try { $exclusions = Get-MpPreference | Select-Object -ExpandProperty ExclusionPath; if ($exclusions -notcontains '!ENGINE_DIR!') { Write-Host 'gen_snapshot.EXE blocked by Windows Security. Adding exclusion...' -ForegroundColor Yellow; Start-Process powershell -Verb RunAs -ArgumentList '-Command Add-MpPreference -ExclusionPath \"!ENGINE_DIR!\" -ErrorAction Stop; Write-Host Exclusion added -ForegroundColor Green' -WindowStyle Hidden -Wait } else { Write-Host 'Windows Security exclusion already active' -ForegroundColor Green } } catch { Write-Host 'Could not check Windows Security exclusions (non-admin)' -ForegroundColor Yellow }}" >nul 2>&1
)

:: --- Locate Android SDK ---
if not defined ANDROID_HOME (
    if defined ANDROID_SDK_ROOT (
        set "ANDROID_HOME=!ANDROID_SDK_ROOT!"
    ) else (
        for %%p in ("%USERPROFILE%\AppData\Local\Android\Sdk" "%LOCALAPPDATA%\Android\Sdk" "C:\Android\Sdk" "C:\Android") do (
            if exist "%%~p" (
                set "ANDROID_HOME=%%~p"
                goto :found_sdk
            )
        )
        echo [WARNING] ANDROID_HOME not set. Build may fail if Android SDK is not found.
    )
)
:found_sdk

set "APP_DIR=%~dp0app"
cd /d "%APP_DIR%"

echo [1/3] Fetching Flutter dependencies...
call "!FLUTTER!" pub get
if %errorlevel% neq 0 (
    echo - Retrying with offline flag...
    call "!FLUTTER!" pub get --offline
)

echo.
echo [2/3] Building Android APK (Release)...
call "!FLUTTER!" build apk --release --target-platform android-arm64,android-arm,android-x64
if %errorlevel% neq 0 (
    echo.
    echo ==============================================================
    echo [ERROR] Android release build failed.
    echo.
    echo Common cause: 'gen_snapshot.EXE' is blocked by Windows
    echo Application Control (Defender / Group Policy).
    echo.
    echo To fix, add an exclusion in Windows Security:
    echo   1. Open Windows Security -^> Virus ^& threat protection
    echo   2. Manage settings -^> Exclusions -^> Add exclusion
    echo   3. Choose FOLDER and add: C:\flutter\bin\cache\artifacts\engine
    echo.
    echo Alternatively, build a DEBUG APK instead (no AOT required):
    echo   flutter build apk --debug
    echo ==============================================================
    pause
    exit /b 1
)

echo.
echo ==========================================
echo              BUILD COMPLETE!
echo    APK: %APP_DIR%\build\app\outputs\flutter-apk\app-release.apk
echo ==========================================
pause
