#!/bin/bash
set -e

# Get the directory of this script and move to repository root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT_DIR"

# Define colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Determine configuration (default to release)
CONFIG="Release"
if [ "$1" = "debug" ] || [ "$1" = "Debug" ]; then
    CONFIG="Debug"
elif [ "$1" = "release" ] || [ "$1" = "Release" ]; then
    CONFIG="Release"
elif [ -n "$1" ]; then
    echo -e "${RED}Error: Unknown configuration '$1'.${NC}"
    echo -e "Usage: $0 [debug|release]"
    exit 1
fi

echo -e "${BLUE}=======================================${NC}"
echo -e "${BLUE} Building Diffuse (${CONFIG} Mode) ${NC}"
echo -e "${BLUE}=======================================${NC}"

# Auto-generate version and build number if not provided in the environment
if [ -z "$VERSION_NAME" ]; then
    VERSION_NAME=$(date +"%y.%m.%d")
fi
if [ -z "$BUILD_NUMBER" ]; then
    BUILD_NUMBER=$(date +"%y%m%d%H%M")
fi

echo -e "Marketing Version: ${GREEN}$VERSION_NAME${NC}"
echo -e "Build Number:      ${GREEN}$BUILD_NUMBER${NC}"

# Run xcodebuild
echo -e "${YELLOW}Running xcodebuild...${NC}"

SIGNING_FLAGS=()
if [ "$CI" = "true" ]; then
    echo -e "${YELLOW}CI environment detected. Using ad-hoc code signing...${NC}"
    SIGNING_FLAGS+=(CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED="NO")
fi

xcodebuild -project Diffuse.xcodeproj -scheme Diffuse -configuration "$CONFIG" -derivedDataPath ./build MARKETING_VERSION="$VERSION_NAME" CURRENT_PROJECT_VERSION="$BUILD_NUMBER" "${SIGNING_FLAGS[@]}" clean build

# Locate and display output
BUILD_PATH="./build/Build/Products/${CONFIG}/Diffuse.app"

if [ -d "$BUILD_PATH" ]; then
    echo -e "${GREEN}=======================================${NC}"
    echo -e "${GREEN} Build Succeeded!${NC}"
    echo -e "${GREEN}=======================================${NC}"
    echo -e "App Binary: ${BLUE}$(pwd)/$BUILD_PATH${NC}"
    
    # If it is release, provide helpful zip instructions
    if [ "$CONFIG" = "Release" ]; then
        ZIP_PATH="$HOME/Desktop/Diffuse-release.zip"
        echo -e "\nTo package this for another Mac, you can run:"
        echo -e "  ${YELLOW}zip -r \"$ZIP_PATH\" \"$BUILD_PATH\"${NC}"
    fi
else
    echo -e "${RED}Build completed, but could not locate the app at $BUILD_PATH${NC}"
    exit 1
fi
