@echo off
:: AeroDrive Windows WebDAV File Size Limit Fixer
:: By default, Windows WebClient limits file transfers to 50MB (Error 0x800700DF).
:: This script sets the limit to 4GB (0xffffffff) and restarts the WebClient service.

echo ========================================================
echo   AeroDrive Windows WebDAV 4GB File Size Limit Fixer
echo ========================================================
echo.

net session >nul 2>&1
if %errorLevel% neq 0 (
    echo [INFO] Requesting Administrator privileges...
    powershell -Command "Start-Process cmd -ArgumentList '/c %~dpnx0' -Verb RunAs"
    exit /b
)

echo [1/2] Updating Windows Registry FileSizeLimitInBytes to 4GB (4294967295 bytes)...
reg add "HKLM\SYSTEM\CurrentControlSet\Services\WebClient\Parameters" /v FileSizeLimitInBytes /t REG_DWORD /d 0xffffffff /f

echo.
echo [2/2] Restarting Windows WebClient service to apply changes...
net stop WebClient
net start WebClient

echo.
echo ========================================================
echo [SUCCESS] Windows WebDAV file size limit increased to 4 GB!
echo You can now open large videos and files directly from Z:!
echo ========================================================
echo.
pause

