#!/bin/bash
set -e

# Get the directory of this script and move to repository root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT_DIR"

echo "Formatting Swift files in Chobi/ and Tests/..."
swift format format --in-place --recursive Chobi Tests

echo "Formatting complete!"
