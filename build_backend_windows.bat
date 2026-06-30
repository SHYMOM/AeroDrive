@echo off
setlocal EnableDelayedExpansion
title Build AeroDrive Go Backend
color 0A

echo ==========================================
echo    AeroDrive - Go Backend Build Script
echo ==========================================
echo.

:: --- Locate Go binary directly ---
set "GOEXE="

where go 2>nul >nul
if %errorlevel% equ 0 (
    for /f "delims=" %%a in ('where go') do (
        if not defined GOEXE set "GOEXE=%%a"
    )
)

if not defined GOEXE (
    if defined GOROOT (
        if exist "!GOROOT!\bin\go.exe" set "GOEXE=!GOROOT!\bin\go.exe"
        if exist "!GOROOT!\bin\go.bat" set "GOEXE=!GOROOT!\bin\go.bat"
    )
)

if not defined GOEXE (
    for %%p in ("C:\Program Files\Go" "C:\Go" "%USERPROFILE%\go" "%USERPROFILE%\scoop\apps\go\current") do (
        if exist "%%~p\bin\go.exe" set "GOEXE=%%~p\bin\go.exe"
        if exist "%%~p\bin\go.bat" set "GOEXE=%%~p\bin\go.bat"
    )
)

if not defined GOEXE (
    echo [ERROR] Go not found! Install from: https://go.dev/dl/
    pause
    exit /b 1
)

echo - Found Go: !GOEXE!
echo.

set "BACKEND_DIR=%~dp0backend"
set "OUTPUT_EXE=%~dp0AeroDrive_Backend.exe"
cd /d "!BACKEND_DIR!"

echo [1/3] Fetching dependencies...
call "!GOEXE!" mod tidy

echo [2/3] Compiling Backend...
call "!GOEXE!" build -ldflags="-w -s" -o "!OUTPUT_EXE!" ./cmd/server/main.go
if !errorlevel! neq 0 (
    echo [ERROR] Go build failed!
    pause
    exit /b 1
)

echo.
echo ==========================================
echo    Build Successful!
echo    Executable: !OUTPUT_EXE!
echo ==========================================
pause
