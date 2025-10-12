#!/usr/bin/env bash
# shellcheck disable=SC2329
# Helper stub definitions for uninstall tests

setup_uninstall_stubs() {
  request_sudo_access() { return 0; }
  start_inline_spinner() { :; }
  stop_inline_spinner() { :; }
  enter_alt_screen() { :; }
  leave_alt_screen() { :; }
  hide_cursor() { :; }
  show_cursor() { :; }
  remove_apps_from_dock() { :; }

  pgrep() { return 1; }
  pkill() { return 0; }
  sudo() { return 0; }

  export -f request_sudo_access start_inline_spinner stop_inline_spinner \
    enter_alt_screen leave_alt_screen hide_cursor show_cursor \
    remove_apps_from_dock pgrep pkill sudo || true
}
