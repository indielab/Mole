#!/bin/bash
# Mole - Common Functions Library
# Shared utilities and functions for all modules

set -euo pipefail

# Color definitions (readonly for safety)
readonly ESC=$'\033'
readonly GREEN="${ESC}[0;32m"
readonly BLUE="${ESC}[0;34m"
readonly YELLOW="${ESC}[1;33m"
readonly PURPLE="${ESC}[0;35m"
readonly RED="${ESC}[0;31m"
readonly NC="${ESC}[0m"

# Logging configuration
readonly LOG_FILE="${HOME}/.config/mole/mole.log"
readonly LOG_MAX_SIZE_DEFAULT=1048576  # 1MB

# Ensure log directory exists
mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true

# Enhanced logging functions with file logging support
log_info() {
    rotate_log
    echo -e "${BLUE}$1${NC}"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] INFO: $1" >> "$LOG_FILE" 2>/dev/null || true
}

log_success() {
    rotate_log
    echo -e "${GREEN}✅ $1${NC}"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] SUCCESS: $1" >> "$LOG_FILE" 2>/dev/null || true
}

log_warning() {
    rotate_log
    echo -e "${YELLOW}⚠️  $1${NC}"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: $1" >> "$LOG_FILE" 2>/dev/null || true
}

log_error() {
    rotate_log
    echo -e "${RED}❌ $1${NC}" >&2
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1" >> "$LOG_FILE" 2>/dev/null || true
}

log_header() {
    rotate_log
    echo -e "\n${PURPLE}▶ $1${NC}"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] SECTION: $1" >> "$LOG_FILE" 2>/dev/null || true
}

# Log file maintenance
rotate_log() {
    local max_size="${MOLE_MAX_LOG_SIZE:-$LOG_MAX_SIZE_DEFAULT}"
    if [[ -f "$LOG_FILE" ]] && [[ $(stat -f%z "$LOG_FILE" 2>/dev/null || echo 0) -gt "$max_size" ]]; then
        mv "$LOG_FILE" "${LOG_FILE}.old" 2>/dev/null || true
        touch "$LOG_FILE" 2>/dev/null || true
    fi
}

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

hide_cursor() {
    printf '\033[?25l'
}

show_cursor() {
    printf '\033[?25h'
}

# Keyboard input handling (simple and robust)
read_key() {
    local key rest
    # Use macOS bash 3.2 compatible read syntax
    IFS= read -r -s -n 1 key || return 1

    # Some terminals can yield empty on Enter with -n1; treat as ENTER
    if [[ -z "$key" ]]; then
        echo "ENTER"
        return 0
    fi

    case "$key" in
        $'\n'|$'\r') echo "ENTER" ;;
        ' ') echo "SPACE" ;;
        'q'|'Q') echo "QUIT" ;;
        'a'|'A') echo "ALL" ;;
        'n'|'N') echo "NONE" ;;
        '?') echo "HELP" ;;
        $'\x1b')
            # Read the next two bytes within 1s; works well on macOS bash 3.2
            if IFS= read -r -s -n 2 -t 1 rest 2>/dev/null; then
                case "$rest" in
                    "[A") echo "UP" ;;
                    "[B") echo "DOWN" ;;
                    "[C") echo "RIGHT" ;;
                    "[D") echo "LEFT" ;;
                    *) echo "OTHER" ;;
                esac
            else
                echo "OTHER"
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
    if [[ ! -e "$path" ]]; then
        echo "N/A"
        return 1
    fi
    du -sh "$path" 2>/dev/null | cut -f1 || echo "N/A"
}

# Convert bytes to human readable format
bytes_to_human() {
    local bytes="$1"
    if [[ ! "$bytes" =~ ^[0-9]+$ ]]; then
        echo "0B"
        return 1
    fi

    if ((bytes >= 1073741824)); then  # >= 1GB
        echo "$bytes" | awk '{printf "%.2fGB", $1/1073741824}'
    elif ((bytes >= 1048576)); then  # >= 1MB
        echo "$bytes" | awk '{printf "%.1fMB", $1/1048576}'
    elif ((bytes >= 1024)); then     # >= 1KB
        echo "$bytes" | awk '{printf "%.0fKB", $1/1024}'
    else
        echo "${bytes}B"
    fi
}

# Calculate directory size in bytes
get_directory_size_bytes() {
    local path="$1"
    if [[ ! -d "$path" ]]; then
        echo "0"
        return 1
    fi
    du -sk "$path" 2>/dev/null | cut -f1 | awk '{print $1 * 1024}' || echo "0"
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

# Load basic configuration
load_config() {
    MOLE_MAX_LOG_SIZE="${MOLE_MAX_LOG_SIZE:-1048576}"
}





# Initialize configuration on sourcing
load_config

# ============================================================================
# App Management Functions
# ============================================================================

# Essential system and critical app patterns that should never be removed
readonly PRESERVED_BUNDLE_PATTERNS=(
    # System essentials
    "com.apple.*"
    "loginwindow"
    "dock"
    "systempreferences"
    "finder"
    "safari"
    "keychain*"
    "security*"
    "bluetooth*"
    "wifi*"
    "network*"
    "tcc"
    "notification*"
    "accessibility*"
    "universalaccess*"
    "HIToolbox*"
    "textinput*"
    "TextInput*"
    "keyboard*"
    "Keyboard*"
    "inputsource*"
    "InputSource*"
    "keylayout*"
    "KeyLayout*"
    "GlobalPreferences"
    ".GlobalPreferences"

    # Input methods (critical for international users)
    "com.tencent.inputmethod.*"
    "com.sogou.*"
    "com.baidu.*"
    "*.inputmethod.*"
    "*input*"
    "*inputmethod*"
    "*InputMethod*"
    "*ime*"
    "*IME*"

    # Cleanup and system tools (avoid infinite loops and preserve licenses)
    "com.nektony.*"                    # App Cleaner & Uninstaller
    "com.macpaw.*"                     # CleanMyMac, CleanMaster
    "com.freemacsoft.AppCleaner"       # AppCleaner
    "com.omnigroup.omnidisksweeper"    # OmniDiskSweeper
    "com.daisydiskapp.*"               # DaisyDisk
    "com.tunabellysoftware.*"          # Disk Utility apps
    "com.grandperspectiv.*"            # GrandPerspective
    "com.binaryfruit.*"                # FusionCast
    "com.CharlesProxy.*"               # Charles Proxy (paid)
    "com.proxyman.*"                   # Proxyman (paid)
    "com.getpaw.*"                     # Paw (paid)

    # Security and password managers (critical data)
    "com.1password.*"                  # 1Password
    "com.agilebits.*"                  # 1Password legacy
    "com.lastpass.*"                   # LastPass
    "com.dashlane.*"                   # Dashlane
    "com.bitwarden.*"                  # Bitwarden
    "com.keepassx.*"                   # KeePassXC

    # Development tools (licenses and settings)
    "com.jetbrains.*"                  # JetBrains IDEs (paid licenses)
    "com.sublimetext.*"                # Sublime Text (paid)
    "com.panic.transmit*"              # Transmit (paid)
    "com.sequelpro.*"                  # Database tools
    "com.sequel-ace.*"
    "com.tinyapp.*"                    # TablePlus (paid)

    # Design tools (expensive licenses)
    "com.adobe.*"                      # Adobe Creative Suite
    "com.bohemiancoding.*"             # Sketch
    "com.figma.*"                      # Figma
    "com.framerx.*"                    # Framer
    "com.zeplin.*"                     # Zeplin
    "com.invisionapp.*"                # InVision
    "com.principle.*"                  # Principle

    # Productivity (important data and licenses)
    "com.omnigroup.*"                  # OmniFocus, OmniGraffle, etc.
    "com.culturedcode.*"               # Things
    "com.todoist.*"                    # Todoist
    "com.bear-writer.*"                # Bear
    "com.typora.*"                     # Typora
    "com.ulyssesapp.*"                 # Ulysses
    "com.literatureandlatte.*"         # Scrivener
    "com.dayoneapp.*"                  # Day One

    # Media and entertainment (licenses)
    "com.spotify.client"               # Spotify (premium accounts)
    "com.apple.FinalCutPro"           # Final Cut Pro
    "com.apple.Motion"                # Motion
    "com.apple.Compressor"            # Compressor
    "com.blackmagic-design.*"         # DaVinci Resolve
    "com.pixelmatorteam.*"            # Pixelmator
)

# Check if bundle should be preserved (system/critical apps)
should_preserve_bundle() {
    local bundle_id="$1"
    for pattern in "${PRESERVED_BUNDLE_PATTERNS[@]}"; do
        if [[ "$bundle_id" == $pattern ]]; then
            return 0
        fi
    done
    return 1
}

# Find and list app-related files (consolidated from duplicates)
find_app_files() {
    local bundle_id="$1"
    local app_name="$2"
    local -a files_to_clean=()

    # Application Support
    [[ -d ~/Library/Application\ Support/"$app_name" ]] && files_to_clean+=("$HOME/Library/Application Support/$app_name")
    [[ -d ~/Library/Application\ Support/"$bundle_id" ]] && files_to_clean+=("$HOME/Library/Application Support/$bundle_id")

    # Caches
    [[ -d ~/Library/Caches/"$bundle_id" ]] && files_to_clean+=("$HOME/Library/Caches/$bundle_id")

    # Preferences
    [[ -f ~/Library/Preferences/"$bundle_id".plist ]] && files_to_clean+=("$HOME/Library/Preferences/$bundle_id.plist")

    # Logs
    [[ -d ~/Library/Logs/"$app_name" ]] && files_to_clean+=("$HOME/Library/Logs/$app_name")
    [[ -d ~/Library/Logs/"$bundle_id" ]] && files_to_clean+=("$HOME/Library/Logs/$bundle_id")

    # Saved Application State
    [[ -d ~/Library/Saved\ Application\ State/"$bundle_id".savedState ]] && files_to_clean+=("$HOME/Library/Saved Application State/$bundle_id.savedState")

    # Containers (sandboxed apps)
    [[ -d ~/Library/Containers/"$bundle_id" ]] && files_to_clean+=("$HOME/Library/Containers/$bundle_id")

    # Group Containers
    while IFS= read -r -d '' container; do
        files_to_clean+=("$container")
    done < <(find ~/Library/Group\ Containers -name "*$bundle_id*" -type d -print0 2>/dev/null)

    # Only print if array has elements to avoid unbound variable error
    if [[ ${#files_to_clean[@]} -gt 0 ]]; then
        printf '%s\n' "${files_to_clean[@]}"
    fi
}

# Calculate total size of files (consolidated from duplicates)
calculate_total_size() {
    local files="$1"
    local total_kb=0

    while IFS= read -r file; do
        if [[ -n "$file" && -e "$file" ]]; then
            local size_kb=$(du -sk "$file" 2>/dev/null | awk '{print $1}' || echo "0")
            ((total_kb += size_kb))
        fi
    done <<< "$files"

    echo "$total_kb"
}
