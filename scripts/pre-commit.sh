#!/bin/bash
# Git pre-commit hook for Mole
# Automatically formats shell scripts before commit
#
# Installation:
#   ln -s ../../scripts/pre-commit.sh .git/hooks/pre-commit
#   chmod +x .git/hooks/pre-commit
#
# Or use the install script:
#   ./scripts/install-hooks.sh

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Only check shell files that are staged
STAGED_SH_FILES=$(git diff --cached --name-only --diff-filter=ACMR | grep -E '\.sh$|^mole$' || true)

if [ -z "$STAGED_SH_FILES" ]; then
    exit 0
fi

echo -e "${YELLOW}Running pre-commit checks on shell files...${NC}"

# Check if shfmt is installed
if ! command -v shfmt &> /dev/null; then
    echo -e "${RED}shfmt is not installed. Install with: brew install shfmt${NC}"
    exit 1
fi

# Check if shellcheck is installed
if ! command -v shellcheck &> /dev/null; then
    echo -e "${RED}shellcheck is not installed. Install with: brew install shellcheck${NC}"
    exit 1
fi

NEEDS_FORMAT=0

# Check formatting
for file in $STAGED_SH_FILES; do
    if ! shfmt -i 4 -ci -sr -d "$file" > /dev/null 2>&1; then
        echo -e "${YELLOW}Formatting $file...${NC}"
        shfmt -i 4 -ci -sr -w "$file"
        git add "$file"
        NEEDS_FORMAT=1
    fi
done

# Run shellcheck
for file in $STAGED_SH_FILES; do
    if ! shellcheck -S warning "$file" > /dev/null 2>&1; then
        echo -e "${YELLOW}ShellCheck warnings in $file:${NC}"
        shellcheck -S warning "$file"
        echo -e "${YELLOW}Continuing with commit (warnings are non-critical)...${NC}"
    fi
done

if [ $NEEDS_FORMAT -eq 1 ]; then
    echo -e "${GREEN}✓ Files formatted and re-staged${NC}"
fi

echo -e "${GREEN}✓ Pre-commit checks passed${NC}"
exit 0
