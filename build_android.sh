#!/bin/bash
# AeroDrive Android Build Script (for Linux/macOS users)
# Run with: ./build_android.sh

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/app" && pwd)"

echo -e "${CYAN}==========================================${NC}"
echo -e "${CYAN}   AeroDrive - Android Build System       ${NC}"
echo -e "${CYAN}==========================================${NC}"
echo ""

cd "$APP_DIR"

echo -e "[1/2] Fetching Flutter dependencies..."
flutter pub get || flutter pub get --offline

echo -e "\n${CYAN}[2/2] Building Android APK (Release)...${NC}"
if flutter build apk --release --target-platform android-arm,android-arm64,android-x64; then
    echo -e "\n${GREEN}==========================================${NC}"
    echo -e "${GREEN}              BUILD COMPLETE!             ${NC}"
    echo -e "${GREEN}    APK: $APP_DIR/build/app/outputs/flutter-apk/app-release.apk${NC}"
    echo -e "${GREEN}==========================================${NC}"
else
    echo -e "${RED}[ERROR] Android build failed!${NC}"
    exit 1
fi
