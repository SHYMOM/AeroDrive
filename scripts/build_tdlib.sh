#!/usr/bin/env bash
# build_tdlib.sh — Cross-compile TDLib for Android using Docker and Android NDK.
# Output goes to app/android/app/src/main/jniLibs/<abi>/
set -euo pipefail

echo "=========================================="
echo "  TDLib Cross-Compile for Android"
echo "=========================================="

if [ $# -lt 1 ]; then
    echo "Usage: $0 <ndk-path>"
    echo "Example: $0 \$ANDROID_NDK_HOME"
    exit 1
fi

NDK_PATH="$1"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OUTPUT_DIR="$SCRIPT_DIR/../app/android/app/src/main/jniLibs"
TDLIB_SRC="$SCRIPT_DIR/../tdlib"
TDLIB_BUILD="$SCRIPT_DIR/../tdlib/build-android"

mkdir -p "$TDLIB_SRC" "$TDLIB_BUILD"

if [ ! -f "$TDLIB_SRC/CMakeLists.txt" ]; then
    echo "Cloning TDLib..."
    git clone --depth 1 --branch v1.8.31 https://github.com/tdlib/td.git "$TDLIB_SRC"
fi

ABIS=("arm64-v8a" "armeabi-v7a" "x86_64")
for ABI in "${ABIS[@]}"; do
    echo "Building for $ABI..."
    BUILD_DIR="$TDLIB_BUILD/$ABI"
    mkdir -p "$BUILD_DIR"
    
    case "$ABI" in
        arm64-v8a)
            TOOLCHAIN="$NDK_PATH/toolchains/llvm/prebuilt/linux-x86_64"
            CC="$TOOLCHAIN/bin/aarch64-linux-android21-clang"
            CXX="$TOOLCHAIN/bin/aarch64-linux-android21-clang++"
            ;;
        armeabi-v7a)
            TOOLCHAIN="$NDK_PATH/toolchains/llvm/prebuilt/linux-x86_64"
            CC="$TOOLCHAIN/bin/armv7a-linux-androideabi21-clang"
            CXX="$TOOLCHAIN/bin/armv7a-linux-androideabi21-clang++"
            ;;
        x86_64)
            TOOLCHAIN="$NDK_PATH/toolchains/llvm/prebuilt/linux-x86_64"
            CC="$TOOLCHAIN/bin/x86_64-linux-android21-clang"
            CXX="$TOOLCHAIN/bin/x86_64-linux-android21-clang++"
            ;;
    esac
    
    cd "$BUILD_DIR"
    cmake "$TDLIB_SRC" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_TOOLCHAIN_FILE="$NDK_PATH/build/cmake/android.toolchain.cmake" \
        -DANDROID_ABI="$ABI" \
        -DANDROID_PLATFORM=android-21 \
        -DCMAKE_C_COMPILER="$CC" \
        -DCMAKE_CXX_COMPILER="$CXX" \
        -DCMAKE_INSTALL_PREFIX="$OUTPUT_DIR/$ABI"
    
    cmake --build . -j$(nproc)
    cmake --install .
    echo "Done building $ABI"
done

echo "=========================================="
echo "  TDLib build complete!"
echo "  Libraries placed in $OUTPUT_DIR"
echo "=========================================="
