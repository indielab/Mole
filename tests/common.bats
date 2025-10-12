#!/usr/bin/env bats

setup_file() {
  PROJECT_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  export PROJECT_ROOT

  ORIGINAL_HOME="${HOME:-}"
  export ORIGINAL_HOME

  HOME="$(mktemp -d "${BATS_TEST_DIRNAME}/tmp-home.XXXXXX")"
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

teardown() {
  unset MO_SPINNER_CHARS || true
}

@test "mo_spinner_chars returns default sequence when unset" {
  result="$(HOME="$HOME" bash --noprofile --norc -c "source '$PROJECT_ROOT/lib/common.sh'; mo_spinner_chars")"
  [ "$result" = "|/-\\" ]
}

@test "mo_spinner_chars respects MO_SPINNER_CHARS override" {
  export MO_SPINNER_CHARS="abcd"
  result="$(HOME="$HOME" MO_SPINNER_CHARS="$MO_SPINNER_CHARS" bash --noprofile --norc -c "source '$PROJECT_ROOT/lib/common.sh'; mo_spinner_chars")"
  [ "$result" = "abcd" ]
}

@test "detect_architecture maps current CPU to friendly label" {
  expected="Intel"
  if [[ "$(uname -m)" == "arm64" ]]; then
    expected="Apple Silicon"
  fi
  result="$(HOME="$HOME" bash --noprofile --norc -c "source '$PROJECT_ROOT/lib/common.sh'; detect_architecture")"
  [ "$result" = "$expected" ]
}

@test "get_free_space returns a non-empty value" {
  result="$(HOME="$HOME" bash --noprofile --norc -c "source '$PROJECT_ROOT/lib/common.sh'; get_free_space")"
  [[ -n "$result" ]]
}

@test "log_info prints message and appends to log file" {
  local message="Informational message from test"
  local stdout_output
  stdout_output="$(HOME="$HOME" bash --noprofile --norc -c "source '$PROJECT_ROOT/lib/common.sh'; log_info '$message'")"
  [[ "$stdout_output" == *"$message"* ]]

  local log_file="$HOME/.config/mole/mole.log"
  [[ -f "$log_file" ]]
  grep -q "INFO: $message" "$log_file"
}

@test "log_error writes to stderr and log file" {
  local message="Something went wrong"
  local stderr_file="$HOME/log_error_stderr.txt"

  HOME="$HOME" bash --noprofile --norc -c "source '$PROJECT_ROOT/lib/common.sh'; log_error '$message' 1>/dev/null 2>'$stderr_file'"

  [[ -s "$stderr_file" ]]
  grep -q "$message" "$stderr_file"

  local log_file="$HOME/.config/mole/mole.log"
  [[ -f "$log_file" ]]
  grep -q "ERROR: $message" "$log_file"
}

@test "bytes_to_human converts byte counts into readable units" {
  output="$(HOME="$HOME" bash --noprofile --norc <<'EOF'
source "$PROJECT_ROOT/lib/common.sh"
bytes_to_human 512
bytes_to_human 2048
bytes_to_human $((5 * 1024 * 1024))
bytes_to_human $((3 * 1024 * 1024 * 1024))
EOF
)"

  bytes_lines=()
  while IFS= read -r line; do
    bytes_lines+=("$line")
  done <<< "$output"

  [ "${bytes_lines[0]}" = "512B" ]
  [ "${bytes_lines[1]}" = "2KB" ]
  [ "${bytes_lines[2]}" = "5.0MB" ]
  [ "${bytes_lines[3]}" = "3.00GB" ]
}

@test "create_temp_file and create_temp_dir are tracked and cleaned" {
  HOME="$HOME" bash --noprofile --norc <<'EOF'
source "$PROJECT_ROOT/lib/common.sh"
create_temp_file > "$HOME/temp_file_path.txt"
create_temp_dir > "$HOME/temp_dir_path.txt"
cleanup_temp_files
EOF

  file_path="$(cat "$HOME/temp_file_path.txt")"
  dir_path="$(cat "$HOME/temp_dir_path.txt")"
  [ ! -e "$file_path" ]
  [ ! -e "$dir_path" ]
  rm -f "$HOME/temp_file_path.txt" "$HOME/temp_dir_path.txt"
}

@test "parallel_execute runs worker across all items" {
  output_file="$HOME/parallel_output.txt"
  HOME="$HOME" bash --noprofile --norc <<'EOF'
source "$PROJECT_ROOT/lib/common.sh"
worker() {
  echo "$1" >> "$HOME/parallel_output.txt"
}
parallel_execute 2 worker "first" "second" "third"
EOF

  sort "$output_file" > "$output_file.sorted"
  results=()
  while IFS= read -r line; do
    results+=("$line")
  done < "$output_file.sorted"

  [ "${#results[@]}" -eq 3 ]
  joined=" ${results[*]} "
  [[ "$joined" == *" first "* ]]
  [[ "$joined" == *" second "* ]]
  [[ "$joined" == *" third "* ]]
  rm -f "$output_file" "$output_file.sorted"
}
