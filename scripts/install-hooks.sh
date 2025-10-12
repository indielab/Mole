#!/bin/bash
# Install git hooks for Mole project
#
# Usage:
#   ./scripts/install-hooks.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

cd "$PROJECT_ROOT"

# Check if this is a git repository
if [ ! -d ".git" ]; then
    echo "Error: Not a git repository"
    exit 1
fi

echo -e "${BLUE}Installing git hooks...${NC}"

# Install pre-commit hook
if [ -f ".git/hooks/pre-commit" ]; then
    echo "Pre-commit hook already exists, creating backup..."
    mv .git/hooks/pre-commit .git/hooks/pre-commit.backup
fi

ln -s ../../scripts/pre-commit.sh .git/hooks/pre-commit
chmod +x .git/hooks/pre-commit

echo -e "${GREEN}✓ Pre-commit hook installed${NC}"
echo ""
echo "The hook will:"
echo "  • Auto-format shell scripts before commit"
echo "  • Run shellcheck on changed files"
echo "  • Show warnings but won't block commits"
echo ""
echo "To uninstall:"
echo "  rm .git/hooks/pre-commit"
echo ""
