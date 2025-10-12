#!/usr/bin/env bats

setup_file() {
  PROJECT_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  export PROJECT_ROOT

  ORIGINAL_HOME="${HOME:-}"
  export ORIGINAL_HOME

  HOME="$(mktemp -d "${BATS_TEST_DIRNAME}/tmp-uninstall-home.XXXXXX")"
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

create_app_artifacts() {
  mkdir -p "$HOME/Applications/TestApp.app"
  mkdir -p "$HOME/Library/Application Support/TestApp"
  mkdir -p "$HOME/Library/Caches/TestApp"
  mkdir -p "$HOME/Library/Containers/com.example.TestApp"
  mkdir -p "$HOME/Library/Preferences"
  touch "$HOME/Library/Preferences/com.example.TestApp.plist"
  mkdir -p "$HOME/Library/Preferences/ByHost"
  touch "$HOME/Library/Preferences/ByHost/com.example.TestApp.ABC123.plist"
  mkdir -p "$HOME/Library/Saved Application State/com.example.TestApp.savedState"
}

@test "find_app_files discovers user-level leftovers" {
  create_app_artifacts

  result="$(HOME="$HOME" bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/common.sh"
find_app_files "com.example.TestApp" "TestApp"
EOF
)"

  [[ "$result" == *"Application Support/TestApp"* ]]
  [[ "$result" == *"Caches/TestApp"* ]]
  [[ "$result" == *"Preferences/com.example.TestApp.plist"* ]]
  [[ "$result" == *"Saved Application State/com.example.TestApp.savedState"* ]]
  [[ "$result" == *"Containers/com.example.TestApp"* ]]
}

@test "calculate_total_size returns aggregate kilobytes" {
  mkdir -p "$HOME/sized"
  dd if=/dev/zero of="$HOME/sized/file1" bs=1024 count=1 >/dev/null 2>&1
  dd if=/dev/zero of="$HOME/sized/file2" bs=1024 count=2 >/dev/null 2>&1

  result="$(HOME="$HOME" bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/common.sh"
files="$(printf '%s\n%s\n' "$HOME/sized/file1" "$HOME/sized/file2")"
calculate_total_size "$files"
EOF
)"

  # Result should be >=3 KB (some filesystems allocate slightly more)
  [ "$result" -ge 3 ]
}

@test "batch_uninstall_applications removes selected app data" {
  create_app_artifacts

  run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/common.sh"
source "$PROJECT_ROOT/lib/batch_uninstall.sh"
source "$PROJECT_ROOT/tests/helpers/uninstall_stubs.sh"
setup_uninstall_stubs

app_bundle="$HOME/Applications/TestApp.app"
mkdir -p "$app_bundle"

related="$(find_app_files "com.example.TestApp" "TestApp")"
encoded_related=$(printf '%s' "$related" | base64 | tr -d '\n')

selected_apps=()
selected_apps+=("0|$app_bundle|TestApp|com.example.TestApp|0|Never")
files_cleaned=0
total_items=0
total_size_cleaned=0

printf '\n' | batch_uninstall_applications >/dev/null

[[ ! -d "$app_bundle" ]] || exit 1
[[ ! -d "$HOME/Library/Application Support/TestApp" ]] || exit 1
[[ ! -d "$HOME/Library/Caches/TestApp" ]] || exit 1
[[ ! -f "$HOME/Library/Preferences/com.example.TestApp.plist" ]] || exit 1
EOF

  [ "$status" -eq 0 ]
}
