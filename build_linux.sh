#!/bin/bash
# AeroDrive Linux Build Script
# Run with: ./build_linux.sh

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/app" && pwd)"
TDLIB_SO_SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/tdlib" && pwd)/libtdjson.so"

echo -e "${CYAN}==========================================${NC}"
echo -e "${CYAN}       AeroDrive - Linux Build System     ${NC}"
echo -e "${CYAN}==========================================${NC}"
echo ""

cd "$APP_DIR"

echo -e "[1/3] Fetching Flutter dependencies..."
flutter pub get || flutter pub get --offline

echo -e "\n${CYAN}[2/3] Building Linux App (Release)...${NC}"
if flutter build linux --release; then
    LINUX_RELEASE_DIR="$APP_DIR/build/linux/x64/release/bundle"
    
    # Inject libtdjson.so if available
    if [ -f "$TDLIB_SO_SRC" ]; then
        echo "- Injecting libtdjson.so into Release bundle..."
        cp "$TDLIB_SO_SRC" "$LINUX_RELEASE_DIR/lib/libtdjson.so"
    else
        echo -e "${RED}[WARNING] libtdjson.so not found at $TDLIB_SO_SRC. You must place it manually in lib/ folder.${NC}"
    fi

    echo -e "${GREEN}- Linux Bundle Location: $LINUX_RELEASE_DIR${NC}"
    
    # Create portable zip
    echo "- Zipping Portable Linux Release..."
    cd "$LINUX_RELEASE_DIR/.."
    tar -czf "$APP_DIR/../AeroDrive_Linux_Portable.tar.gz" bundle
    
    echo -e "\n${GREEN}==========================================${NC}"
    echo -e "${GREEN}              BUILD COMPLETE!             ${NC}"
    echo -e "${GREEN}    Archive: AeroDrive_Linux_Portable.tar.gz${NC}"
    echo -e "${GREEN}==========================================${NC}"
else
    echo -e "${RED}[ERROR] Linux build failed!${NC}"
    exit 1
fi
