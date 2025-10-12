#!/bin/bash
# Format all shell scripts in the Mole project
#
# Usage:
#   ./scripts/format.sh           # Format all scripts
#   ./scripts/format.sh --check   # Check only, don't modify

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

CHECK_ONLY=false

# Parse arguments
if [[ "${1:-}" == "--check" ]]; then
    CHECK_ONLY=true
elif [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    cat << 'EOF'
Usage: ./scripts/format.sh [--check]

Format shell scripts using shfmt.

Options:
  --check    Check formatting without modifying files
  --help     Show this help

Install: brew install shfmt
EOF
    exit 0
fi

# Check if shfmt is installed
if ! command -v shfmt > /dev/null 2>&1; then
    echo "Error: shfmt not installed"
    echo "Install: brew install shfmt"
    exit 1
fi

# Find all shell scripts
cd "$PROJECT_ROOT"

# shfmt options: -i 4 (4 spaces), -ci (indent switch cases), -sr (space after redirect)
if [[ "$CHECK_ONLY" == "true" ]]; then
    echo "Checking formatting..."
    if shfmt -i 4 -ci -sr -d . > /dev/null 2>&1; then
        echo "✓ All scripts properly formatted"
        exit 0
    else
        echo "✗ Some scripts need formatting:"
        shfmt -i 4 -ci -sr -d .
        echo ""
        echo "Run './scripts/format.sh' to fix"
        exit 1
    fi
else
    echo "Formatting scripts..."
    shfmt -i 4 -ci -sr -w .
    echo "✓ Done"
fi
