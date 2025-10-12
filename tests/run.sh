#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

if command -v shellcheck > /dev/null 2>&1; then
    SHELLCHECK_TARGETS=()
    while IFS= read -r file; do
        SHELLCHECK_TARGETS+=("$file")
    done < <(find "$PROJECT_ROOT/tests" -type f \( -name '*.bats' -o -name '*.sh' \) | sort)

    if [[ ${#SHELLCHECK_TARGETS[@]} -gt 0 ]]; then
        shellcheck --rcfile "$PROJECT_ROOT/.shellcheckrc" "${SHELLCHECK_TARGETS[@]}"
    else
        echo "No shell files to lint under tests/." >&2
    fi
else
    echo "shellcheck not found; skipping linting." >&2
fi

if command -v bats > /dev/null 2>&1; then
    cd "$PROJECT_ROOT"

    if [[ -z "${TERM:-}" ]]; then
        export TERM="xterm-256color"
    fi

    if [[ $# -eq 0 ]]; then
        set -- tests
    fi

    if [[ -t 1 ]]; then
        bats -p "$@"
    else
        TERM="${TERM:-xterm-256color}" bats --tap "$@"
    fi
else
    cat << 'EOF' >&2
bats is required to run Mole's test suite.
Install via Homebrew with 'brew install bats-core' or via npm with 'npm install -g bats'.
EOF
    exit 1
fi
