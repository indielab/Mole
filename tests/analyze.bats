#!/usr/bin/env bats

setup_file() {
    PROJECT_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
    export PROJECT_ROOT

    ORIGINAL_HOME="${HOME:-}"
    export ORIGINAL_HOME

    HOME="$(mktemp -d "${BATS_TEST_DIRNAME}/tmp-analyze-home.XXXXXX")"
    export HOME
}

teardown_file() {
    rm -rf "$HOME"
    if [[ -n "${ORIGINAL_HOME:-}" ]]; then
        export HOME="$ORIGINAL_HOME"
    fi
}

setup() {
    export TERM="dumb"
    rm -rf "${HOME:?}"/*
    mkdir -p "$HOME"
}

@test "scan_directories lists largest folders first" {
    run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" bash --noprofile --norc << 'EOF'
set -euo pipefail
source "$PROJECT_ROOT/bin/analyze.sh"

root="$HOME/analyze-root"
mkdir -p "$root/Small" "$root/Large"
printf 'tiny' > "$root/Small/file.txt"
dd if=/dev/zero of="$root/Large/big.dat" bs=1024 count=200 >/dev/null 2>&1

output_file="$HOME/directories.txt"
scan_directories "$root" "$output_file" 1

head -n1 "$output_file"
EOF

    [ "$status" -eq 0 ]
    [[ "$output" == *"Large"* ]]
}

@test "aggregate_by_directory sums child sizes per parent" {
    run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" bash --noprofile --norc << 'EOF'
set -euo pipefail
source "$PROJECT_ROOT/bin/analyze.sh"

root="$HOME/group"
mkdir -p "$root/a" "$root/b"

input_file="$HOME/files.txt"
cat > "$input_file" <<LIST
1024|$root/a/file1
2048|$root/a/file2
512|$root/b/data.bin
LIST

output_file="$HOME/aggregated.txt"
aggregate_by_directory "$input_file" "$output_file"

cat "$output_file"
EOF

    [ "$status" -eq 0 ]
    [[ "$output" == *"3072|$HOME/group/a/"* ]]
    [[ "$output" == *"512|$HOME/group/b/"* ]]
}
