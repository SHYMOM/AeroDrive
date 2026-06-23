@echo off
title Build AeroDrive Go Backend
color 0A

:: Set PATH locally
set "PATH=C:\Program Files\Go\bin;%~dp0go-bin\go\bin;%PATH%"

set "BACKEND_DIR=%~dp0backend"
set "OUTPUT_EXE=%~dp0AeroDrive_Backend.exe"

echo ==========================================
echo    AeroDrive - Go Backend Build Script
echo ==========================================
echo.

cd /d "%BACKEND_DIR%"

echo [1/3] Checking Go installation...
call go version >nul 2>&1
if %errorlevel% neq 0 (
    echo [ERROR] Go is not installed or not in PATH.
    pause
    exit /b 1
)

echo [2/3] Fetching dependencies...
call go mod tidy

echo [3/3] Compiling Backend...
call go build -ldflags="-w -s" -o "%OUTPUT_EXE%" ./cmd/server/main.go
if %errorlevel% neq 0 (
    echo [ERROR] Go build failed!
    pause
    exit /b 1
)

echo.
echo ==========================================
echo    Build Successful!
echo    Executable: %OUTPUT_EXE%
echo ==========================================
pause
