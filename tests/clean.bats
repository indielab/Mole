#!/usr/bin/env bats

setup_file() {
  PROJECT_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  export PROJECT_ROOT

  ORIGINAL_HOME="${HOME:-}"
  export ORIGINAL_HOME

  HOME="$(mktemp -d "${BATS_TEST_DIRNAME}/tmp-clean-home.XXXXXX")"
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
  export TERM="xterm-256color"
  rm -rf "${HOME:?}"/*
  rm -rf "$HOME/Library" "$HOME/.config"
  mkdir -p "$HOME/Library/Caches" "$HOME/.config/mole"
}

@test "mo clean --dry-run skips system cleanup in non-interactive mode" {
  run env HOME="$HOME" "$PROJECT_ROOT/mole" clean --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"Dry Run Mode"* ]]
  [[ "$output" != *"Deep system-level cleanup"* ]]
}

@test "mo clean --dry-run reports user cache without deleting it" {
  mkdir -p "$HOME/Library/Caches/TestApp"
  echo "cache data" > "$HOME/Library/Caches/TestApp/cache.tmp"

  run env HOME="$HOME" "$PROJECT_ROOT/mole" clean --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"User app cache"* ]]
  [[ "$output" == *"Potential space"* ]]
  [ -f "$HOME/Library/Caches/TestApp/cache.tmp" ]
}

@test "mo clean honors whitelist entries" {
  mkdir -p "$HOME/Library/Caches/WhitelistedApp"
  echo "keep me" > "$HOME/Library/Caches/WhitelistedApp/data.tmp"

  cat > "$HOME/.config/mole/whitelist" <<EOF
$HOME/Library/Caches/WhitelistedApp*
EOF

  run env HOME="$HOME" "$PROJECT_ROOT/mole" clean --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"Protected: 1"* ]]
  [ -f "$HOME/Library/Caches/WhitelistedApp/data.tmp" ]
}
