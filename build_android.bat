@echo off
setlocal EnableDelayedExpansion
title Build AeroDrive Android
color 0B

set "LOG_DATE=%DATE:~-4,4%%DATE:~-10,2%%DATE:~-7,2%"
set "LOG_TIME=%TIME:~0,2%%TIME:~3,2%%TIME:~6,2%"
set "LOG_TIME=!LOG_TIME: =0!"
set "BUILD_LOG=%USERPROFILE%\Desktop\aerodrive_build_!LOG_DATE!_!LOG_TIME!.log"

echo ==========================================
echo    AeroDrive Android Build Script
echo ==========================================
echo.
echo Build log: !BUILD_LOG!
echo.

(
echo ==========================================
echo    AeroDrive Android Build - %DATE% %TIME%
echo ==========================================
echo.
) > "!BUILD_LOG!"

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
    echo [ERROR] Flutter not found! >> "!BUILD_LOG!"
    echo.
    echo Log saved to: !BUILD_LOG!
    pause
    exit /b 1
)

echo - Found Flutter: !FLUTTER!
echo - Found Flutter: !FLUTTER! >> "!BUILD_LOG!"
echo.

:: --- Auto-add Windows Defender exclusion for gen_snapshot.EXE ---
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
        echo [WARNING] ANDROID_HOME not set. >> "!BUILD_LOG!"
    )
)
:found_sdk

set "APP_DIR=%~dp0app"
cd /d "%APP_DIR%"

echo [1/4] Cleaning previous build...
echo [1/4] Cleaning previous build... >> "!BUILD_LOG!"
call "!FLUTTER!" clean >> "!BUILD_LOG!" 2>&1

echo.
echo [2/4] Fetching Flutter dependencies...
echo [2/4] Fetching Flutter dependencies... >> "!BUILD_LOG!"
call "!FLUTTER!" pub get >> "!BUILD_LOG!" 2>&1
if %errorlevel% neq 0 (
    echo - Retrying with offline flag...
    echo - Retrying with offline flag... >> "!BUILD_LOG!"
    call "!FLUTTER!" pub get --offline >> "!BUILD_LOG!" 2>&1
)

echo.
echo [3/4] Building Android APK (Release)...
echo [3/4] Building Android APK (Release)... >> "!BUILD_LOG!"
echo.
call "!FLUTTER!" build apk --release --target-platform android-arm64,android-arm,android-x64 >> "!BUILD_LOG!" 2>&1

if %errorlevel% neq 0 (
    echo.
    echo ==============================================================
    echo [ERROR] Android release build FAILED.
    echo ==============================================================
    echo.
    echo Full build log: !BUILD_LOG!
    echo.
    echo --- Last 30 lines of build log ---
    echo =================================
    powershell -Command "Get-Content '!BUILD_LOG!' -Tail 30"
    echo =================================
    echo.
    echo Common issues:
    echo   1. 'gen_snapshot.EXE' blocked by Windows Defender
    echo      - Add folder exclusion for: C:\flutter\bin\cache\artifacts\engine
    echo.
    echo   2. Missing or incompatible Kotlin/Gradle plugin versions
    echo      - Run: flutter clean
    echo      - Run: flutter pub get
    echo.
    echo   3. Outdated Android SDK/NDK
    echo      - Run: flutter doctor -v
    echo.
    echo Log saved to: !BUILD_LOG!
    echo You can now copy the log from the path above.
    echo.
    pause
    exit /b 1
)

echo.
echo ==========================================
echo              BUILD COMPLETE!
echo    APK: %APP_DIR%\build\app\outputs\flutter-apk\app-release.apk
echo ==========================================
echo.
echo Build log: !BUILD_LOG!
echo.
echo Build SUCCESS >> "!BUILD_LOG!"
pause
