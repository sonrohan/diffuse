#!/bin/bash
set -e

# Get the directory of this script and move to repository root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT_DIR"

echo "Linting Swift files in diffuse/ and root..."
swift format lint --strict --recursive diffuse ArchitectureTests.swift

echo "Linting complete! All files conform to swift-format specifications."
