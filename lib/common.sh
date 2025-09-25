#!/bin/bash
# Mac Tools - Common Functions Library
# Shared utilities and functions for all modules

# Color definitions
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
PURPLE='\033[0;35m'
RED='\033[0;31m'
NC='\033[0m'

# Logging functions
log_info() { echo -e "${BLUE}$1${NC}"; }
log_success() { echo -e "${GREEN}✅ $1${NC}"; }
log_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
log_error() { echo -e "${RED}❌ $1${NC}"; }
log_header() { echo -e "\n${PURPLE}▶ $1${NC}"; }

# System detection
detect_architecture() {
    if [[ "$(uname -m)" == "arm64" ]]; then
        echo "Apple Silicon"
    else
        echo "Intel"
    fi
}

get_free_space() {
    df -h / | awk 'NR==2 {print $4}'
}

# Common UI functions
clear_screen() {
    printf '\033[2J\033[H'
}

# Keyboard input handling (simple and robust)
read_key() {
    local key rest
    IFS= read -rsn1 key || return 1

    # Some terminals can yield empty on Enter with -n1; treat as ENTER
    if [[ -z "$key" ]]; then
        echo "ENTER"
        return 0
    fi

    case "$key" in
        $'\n'|$'\r') echo "ENTER" ;;
        ' ') echo " " ;;
        'q'|'Q') echo "QUIT" ;;
        'a'|'A') echo "ALL" ;;
        'n'|'N') echo "NONE" ;;
        '?') echo "HELP" ;;
        $'\x1b')
            # Read the next two bytes within 1s; works well on macOS bash 3.2
            if IFS= read -rsn2 -t 1 rest 2>/dev/null; then
                case "$rest" in
                    "[A") echo "UP" ;;
                    "[B") echo "DOWN" ;;
                    "[C") echo "RIGHT" ;;
                    "[D") echo "LEFT" ;;
                    *) echo "ESC" ;;
                esac
            else
                echo "ESC"
            fi
            ;;
        *) echo "OTHER" ;;
    esac
}

# Menu display helper
show_menu_option() {
    local number="$1"
    local text="$2"
    local selected="$3"

    if [[ "$selected" == "true" ]]; then
        echo -e "${BLUE}▶ $number. $text${NC}"
    else
        echo "  $number. $text"
    fi
}

# Error handling
handle_error() {
    local message="$1"
    local exit_code="${2:-1}"

    log_error "$message"
    exit "$exit_code"
}

# File size utilities
get_human_size() {
    local path="$1"
    du -sh "$path" 2>/dev/null | cut -f1 || echo "N/A"
}

# Permission checks
check_sudo() {
    if ! sudo -n true 2>/dev/null; then
        return 1
    fi
    return 0
}

request_sudo() {
    echo "This operation requires administrator privileges."
    echo -n "Please enter your password: "
    read -s password
    echo
    if echo "$password" | sudo -S true 2>/dev/null; then
        return 0
    else
        log_error "Invalid password or cancelled"
        return 1
    fi
}
