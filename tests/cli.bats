#!/usr/bin/env bats

setup_file() {
    PROJECT_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
    export PROJECT_ROOT

    ORIGINAL_HOME="${HOME:-}"
    export ORIGINAL_HOME

    HOME="$(mktemp -d "${BATS_TEST_DIRNAME}/tmp-cli-home.XXXXXX")"
    export HOME

    mkdir -p "$HOME"
}

teardown_file() {
    rm -rf "$HOME"
    if [[ -n "${ORIGINAL_HOME:-}" ]]; then
        export HOME="$ORIGINAL_HOME"
    fi
}

setup() {
    rm -rf "$HOME/.config"
    mkdir -p "$HOME"
}

@test "mole --help prints command overview" {
    run env HOME="$HOME" "$PROJECT_ROOT/mole" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"mo clean"* ]]
    [[ "$output" == *"mo analyze"* ]]
}

@test "mole --version reports script version" {
    expected_version="$(grep '^VERSION=' "$PROJECT_ROOT/mole" | head -1 | sed 's/VERSION=\"\(.*\)\"/\1/')"
    run env HOME="$HOME" "$PROJECT_ROOT/mole" --version
    [ "$status" -eq 0 ]
    [[ "$output" == *"$expected_version"* ]]
}

@test "mole unknown command returns error" {
    run env HOME="$HOME" "$PROJECT_ROOT/mole" unknown-command
    [ "$status" -ne 0 ]
    [[ "$output" == *"Unknown command: unknown-command"* ]]
}

@test "touchid status reports current configuration" {
    run env HOME="$HOME" "$PROJECT_ROOT/mole" touchid status
    [ "$status" -eq 0 ]
    [[ "$output" == *"Touch ID"* ]]
}
