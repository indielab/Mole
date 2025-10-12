#!/usr/bin/env bats

setup_file() {
    PROJECT_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
    export PROJECT_ROOT
}

@test "shellcheck passes for test scripts" {
    if ! command -v shellcheck > /dev/null 2>&1; then
        skip "shellcheck not installed"
    fi

    run env PROJECT_ROOT="$PROJECT_ROOT" bash --noprofile --norc << 'EOF'
set -euo pipefail
cd "$PROJECT_ROOT"
targets=()
while IFS= read -r file; do
  targets+=("$file")
done < <(find "$PROJECT_ROOT/tests" -type f \( -name '*.bats' -o -name '*.sh' \) | sort)
if [[ ${#targets[@]} -eq 0 ]]; then
  echo "No test shell files found"
  exit 0
fi
shellcheck --rcfile "$PROJECT_ROOT/.shellcheckrc" "${targets[@]}"
EOF

    printf '%s\n' "$output" >&3
    [ "$status" -eq 0 ]
}
