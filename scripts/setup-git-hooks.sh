#!/bin/bash
set -e

# Get the directory of this script and move to repository root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT_DIR"

HOOK_FILE=".git/hooks/pre-commit"

if [ ! -d ".git" ]; then
    echo "Error: .git directory not found. Please run this script from inside a git repository."
    exit 1
fi

echo "Setting up pre-commit git hook for swift-format..."

# Create pre-commit hook file
cat << 'EOF' > "$HOOK_FILE"
#!/bin/bash
# Automatically generated pre-commit hook by swift-format setup

# Find all staged Swift files that are modified, added, or renamed (excluding deleted files)
STAGED_SWIFT_FILES=$(git diff --cached --name-only --diff-filter=ACM | grep -E '\.swift$')

if [ -n "$STAGED_SWIFT_FILES" ]; then
    echo "Pre-commit: Formatting staged Swift files..."
    
    # Check if swift-format is accessible via swift format command
    if command -v swift &>/dev/null && swift format --version &>/dev/null; then
        for file in $STAGED_SWIFT_FILES; do
            if [ -f "$file" ]; then
                swift format format --in-place "$file"
                git add "$file"
            fi
        done
        echo "Pre-commit: Formatting complete!"
    else
        echo "Pre-commit Warning: 'swift format' is not available in path. Skipping auto-formatting."
    fi
fi
EOF

chmod +x "$HOOK_FILE"
echo "Pre-commit hook installed successfully at $HOOK_FILE!"
