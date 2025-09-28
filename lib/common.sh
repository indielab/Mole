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

# Safe file operation with backup
safe_remove() {
    local path="$1"
    local backup_dir="${2:-/tmp/mole_backup_$(date +%s)}"
    local backup_enabled="${MOLE_BACKUP_ENABLED:-true}"

    if [[ ! -e "$path" ]]; then
        return 0
    fi

    if [[ "$backup_enabled" == "true" ]]; then
        # Create backup directory if it doesn't exist
        mkdir -p "$backup_dir" 2>/dev/null || return 1

        local basename_path
        basename_path=$(basename "$path")

        if ! cp -R "$path" "$backup_dir/$basename_path" 2>/dev/null; then
            log_warning "Backup failed for $path, skipping removal"
            return 1
        fi
        log_info "Backup created at $backup_dir/$basename_path"
    fi

    rm -rf "$path" 2>/dev/null || true
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

# Configuration management
readonly CONFIG_FILE="${HOME}/.config/mole/config"

# Load configuration with defaults
load_config() {
    # Default configuration
    MOLE_LOG_LEVEL="${MOLE_LOG_LEVEL:-INFO}"
    MOLE_AUTO_CONFIRM="${MOLE_AUTO_CONFIRM:-false}"
    MOLE_BACKUP_ENABLED="${MOLE_BACKUP_ENABLED:-true}"
    MOLE_MAX_LOG_SIZE="${MOLE_MAX_LOG_SIZE:-1048576}"
    MOLE_PARALLEL_JOBS="${MOLE_PARALLEL_JOBS:-}"  # Empty means auto-detect

    # Load user configuration if exists
    if [[ -f "$CONFIG_FILE" ]]; then
        source "$CONFIG_FILE" 2>/dev/null || true
    fi
}

# Save configuration
save_config() {
    mkdir -p "$(dirname "$CONFIG_FILE")" 2>/dev/null || return 1
    cat > "$CONFIG_FILE" << EOF
# Mole Configuration File
# Generated on $(date)

# Log level: DEBUG, INFO, WARNING, ERROR
MOLE_LOG_LEVEL="$MOLE_LOG_LEVEL"

# Auto confirm operations (true/false)
MOLE_AUTO_CONFIRM="$MOLE_AUTO_CONFIRM"

# Enable backup before deletion (true/false)
MOLE_BACKUP_ENABLED="$MOLE_BACKUP_ENABLED"

# Maximum log file size in bytes
MOLE_MAX_LOG_SIZE="$MOLE_MAX_LOG_SIZE"

# Number of parallel jobs for operations (empty = auto-detect)
MOLE_PARALLEL_JOBS="$MOLE_PARALLEL_JOBS"
EOF
}

# Progress tracking
# Use parameter expansion for portable global initialization (macOS bash lacks declare -g).
: "${PROGRESS_CURRENT:=0}"
: "${PROGRESS_TOTAL:=0}"
: "${PROGRESS_MESSAGE:=}"

# Initialize progress tracking
init_progress() {
    PROGRESS_CURRENT=0
    PROGRESS_TOTAL="$1"
    PROGRESS_MESSAGE="${2:-Processing}"
}

# Update progress
update_progress() {
    PROGRESS_CURRENT="$1"
    local message="${2:-$PROGRESS_MESSAGE}"
    local percentage=$((PROGRESS_CURRENT * 100 / PROGRESS_TOTAL))

    # Create progress bar
    local bar_length=20
    local filled_length=$((percentage * bar_length / 100))
    local bar=""

    for ((i=0; i<filled_length; i++)); do
        bar="${bar}█"
    done

    for ((i=filled_length; i<bar_length; i++)); do
        bar="${bar}░"
    done

    printf "\r${BLUE}[%s] %3d%% %s (%d/%d)${NC}" "$bar" "$percentage" "$message" "$PROGRESS_CURRENT" "$PROGRESS_TOTAL"

    if [[ $PROGRESS_CURRENT -eq $PROGRESS_TOTAL ]]; then
        echo
    fi
}

# Spinner for indeterminate progress
: "${SPINNER_PID:=}"

start_spinner() {
    local message="${1:-Working}"
    stop_spinner  # Stop any existing spinner

    (
        local spin='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
        local i=0
        while true; do
            printf "\r${BLUE}%s %s${NC}" "${spin:$i:1}" "$message"
            ((i++))
            if [[ $i -eq ${#spin} ]]; then
                i=0
            fi
            sleep 0.1
        done
    ) &
    SPINNER_PID=$!
}

stop_spinner() {
    if [[ -n "$SPINNER_PID" ]]; then
        kill "$SPINNER_PID" 2>/dev/null || true
        wait "$SPINNER_PID" 2>/dev/null || true
        SPINNER_PID=""
        printf "\r\033[K"  # Clear the line
    fi
}

# Calculate optimal parallel jobs based on system resources
get_optimal_parallel_jobs() {
    local operation_type="${1:-default}"
    local optimal_parallel=4

    # Try to detect optimal parallel jobs based on CPU cores
    if command -v nproc >/dev/null 2>&1; then
        optimal_parallel=$(nproc)
    elif command -v sysctl >/dev/null 2>&1; then
        optimal_parallel=$(sysctl -n hw.ncpu 2>/dev/null || echo 4)
    fi

    # Apply operation-specific limits
    case "$operation_type" in
        "scan")
            # For scanning: min 2, max 8
            if [[ $optimal_parallel -lt 2 ]]; then
                optimal_parallel=2
            elif [[ $optimal_parallel -gt 8 ]]; then
                optimal_parallel=8
            fi
            ;;
        "clean")
            # For file operations: min 2, max 6 (more conservative)
            if [[ $optimal_parallel -lt 2 ]]; then
                optimal_parallel=2
            elif [[ $optimal_parallel -gt 6 ]]; then
                optimal_parallel=6
            fi
            ;;
        *)
            # Default: min 2, max 4 (safest)
            if [[ $optimal_parallel -lt 2 ]]; then
                optimal_parallel=2
            elif [[ $optimal_parallel -gt 4 ]]; then
                optimal_parallel=4
            fi
            ;;
    esac

    # Use configured value if available, otherwise use calculated optimal
    if [[ -n "${MOLE_PARALLEL_JOBS:-}" ]]; then
        echo "$MOLE_PARALLEL_JOBS"
    else
        echo "$optimal_parallel"
    fi
}

# Initialize configuration on sourcing
load_config
