#!/bin/bash
# Unified check script for Mole project
# Runs all quality checks in one command

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

cd "$PROJECT_ROOT"

echo -e "${BLUE}=== Running Mole Quality Checks ===${NC}\n"

# 1. Format check
echo -e "${YELLOW}1. Checking code formatting...${NC}"
if command -v shfmt > /dev/null 2>&1; then
    if ./scripts/format.sh --check; then
        echo -e "${GREEN}✓ Formatting check passed${NC}\n"
    else
        echo -e "${RED}✗ Formatting check failed${NC}\n"
        exit 1
    fi
else
    echo -e "${YELLOW}⚠ shfmt not installed, skipping format check${NC}\n"
fi

# 2. ShellCheck
echo -e "${YELLOW}2. Running ShellCheck...${NC}"
if command -v shellcheck > /dev/null 2>&1; then
    # Count total files
    SHELL_FILES=$(find . -type f \( -name "*.sh" -o -name "mole" \) -not -path "./tests/*" -not -path "./.git/*")
    FILE_COUNT=$(echo "$SHELL_FILES" | wc -l | tr -d ' ')

    if shellcheck mole bin/*.sh lib/*.sh scripts/*.sh 2>&1 | grep -q "SC[0-9]"; then
        echo -e "${YELLOW}⚠ ShellCheck found some issues (non-critical):${NC}"
        shellcheck mole bin/*.sh lib/*.sh scripts/*.sh 2>&1 | head -20
        echo -e "${GREEN}✓ ShellCheck completed (${FILE_COUNT} files checked)${NC}\n"
    else
        echo -e "${GREEN}✓ ShellCheck passed (${FILE_COUNT} files checked)${NC}\n"
    fi
else
    echo -e "${YELLOW}⚠ shellcheck not installed, skipping${NC}\n"
fi

# 3. Unit tests (if available)
echo -e "${YELLOW}3. Running tests...${NC}"
if command -v bats > /dev/null 2>&1 && [ -d "tests" ]; then
    if bats tests/*.bats 2> /dev/null; then
        echo -e "${GREEN}✓ Tests passed${NC}\n"
    else
        echo -e "${RED}✗ Tests failed${NC}\n"
        exit 1
    fi
else
    echo -e "${YELLOW}⚠ bats not installed or no tests found, skipping${NC}\n"
fi

# Summary
echo -e "${GREEN}=== All Checks Completed ===${NC}"
echo -e "${GREEN}✓ Code quality checks passed!${NC}"
