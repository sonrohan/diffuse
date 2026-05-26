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

# Run xcodebuild
echo -e "${YELLOW}Running xcodebuild...${NC}"
xcodebuild -project Diffuse.xcodeproj -scheme Diffuse -configuration "$CONFIG" -derivedDataPath ./build clean build

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
