# AeroDrive - TDLib Binary Downloader
# This script fetches pre-compiled tdjson binaries for Windows and Android.

$ErrorActionPreference = "Stop"

# URLs for pre-compiled TDLib binaries (Example using community builds for v1.8.x)
$windowsUrl = "https://github.com/Kylmakalle/tdlib-dart/releases/download/v1.8.19/tdjson.dll"
$androidArm64Url = "https://github.com/Kylmakalle/tdlib-dart/releases/download/v1.8.19/libtdjson-arm64-v8a.so"
$androidArmUrl = "https://github.com/Kylmakalle/tdlib-dart/releases/download/v1.8.19/libtdjson-armeabi-v7a.so"

$windowsDest = "..\app\windows\tdjson.dll"
$androidArm64DestDir = "..\app\android\app\src\main\jniLibs\arm64-v8a"
$androidArmDestDir = "..\app\android\app\src\main\jniLibs\armeabi-v7a"

Write-Host "=========================================="
Write-Host "  AeroDrive - Downloading TDLib Binaries  "
Write-Host "=========================================="

# Create directories if they don't exist
if (!(Test-Path $androidArm64DestDir)) { New-Item -ItemType Directory -Force -Path $androidArm64DestDir | Out-Null }
if (!(Test-Path $androidArmDestDir)) { New-Item -ItemType Directory -Force -Path $androidArmDestDir | Out-Null }
if (!(Test-Path "..\app\windows")) { New-Item -ItemType Directory -Force -Path "..\app\windows" | Out-Null }

Write-Host "`n[1/3] Downloading Windows tdjson.dll..."
try {
    Invoke-WebRequest -Uri $windowsUrl -OutFile $windowsDest
    Write-Host "Success: $windowsDest" -ForegroundColor Green
} catch {
    Write-Host "Failed to download Windows binary. You may need to download it manually from https://github.com/Kylmakalle/tdlib-dart/releases" -ForegroundColor Yellow
}

Write-Host "`n[2/3] Downloading Android arm64-v8a libtdjson.so..."
try {
    Invoke-WebRequest -Uri $androidArm64Url -OutFile "$androidArm64DestDir\libtdjson.so"
    Write-Host "Success: $androidArm64DestDir\libtdjson.so" -ForegroundColor Green
} catch {
    Write-Host "Failed to download Android arm64-v8a binary." -ForegroundColor Yellow
}

Write-Host "`n[3/3] Downloading Android armeabi-v7a libtdjson.so..."
try {
    Invoke-WebRequest -Uri $androidArmUrl -OutFile "$androidArmDestDir\libtdjson.so"
    Write-Host "Success: $androidArmDestDir\libtdjson.so" -ForegroundColor Green
} catch {
    Write-Host "Failed to download Android armeabi-v7a binary." -ForegroundColor Yellow
}

Write-Host "`nDone! Pre-compiled binaries are set up." -ForegroundColor Cyan
