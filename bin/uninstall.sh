#!/bin/bash
# Mac Tools - Uninstall Module
# Interactive application uninstaller with keyboard navigation
#
# Usage:
#   uninstall.sh          # Launch interactive uninstaller
#   uninstall.sh --help   # Show help information

set -euo pipefail

# Get script directory and source common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"
source "$SCRIPT_DIR/../lib/menu.sh"
source "$SCRIPT_DIR/../lib/app_selector.sh"
source "$SCRIPT_DIR/../lib/batch_uninstall.sh"

# Basic preserved bundle patterns
PRESERVED_BUNDLE_PATTERNS=(
    "com.apple.*"
    "com.nektony.*"
)

# Check if bundle should be preserved (system apps)
should_preserve_bundle() {
    local bundle_id="$1"
    for pattern in "${PRESERVED_BUNDLE_PATTERNS[@]}"; do
        if [[ "$bundle_id" == $pattern ]]; then
            return 0
        fi
    done
    return 1
}

# Help information
show_help() {
    echo "Mole - Interactive App Uninstaller"
    echo "========================================"
    echo ""
    echo "Description: Interactive tool to uninstall applications and clean their data"
    echo ""
    echo "Features:"
    echo "  • Navigate with ↑/↓ arrow keys"
    echo "  • Select/deselect apps with SPACE"
    echo "  • Confirm selection with ENTER"
    echo "  • Quit anytime with 'q'"
    echo "  • Apps sorted by last usage time"
    echo "  • Comprehensive cleanup of app data"
    echo ""
    echo "Usage:"
    echo "  ./uninstall.sh          Launch interactive uninstaller"
    echo "  ./uninstall.sh --help   Show this help message"
    echo ""
    echo "What gets cleaned:"
    echo "  • Application bundle"
    echo "  • Application Support data"
    echo "  • Cache files"
    echo "  • Preference files"
    echo "  • Log files"
    echo "  • Saved application state"
    echo "  • Container data (sandboxed apps)"
    echo ""
}

# Parse arguments
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    show_help
    exit 0
fi

# Initialize global variables
declare -a selected_apps=()
declare -a apps_data=()
declare -a selection_state=()
current_line=0
total_items=0
files_cleaned=0
total_size_cleaned=0

# Get app last used date in human readable format
get_app_last_used() {
    local app_path="$1"
    local last_used=$(mdls -name kMDItemLastUsedDate -raw "$app_path" 2>/dev/null)

    if [[ "$last_used" == "(null)" || -z "$last_used" ]]; then
        echo "Never"
    else
        local last_used_epoch=$(date -j -f "%Y-%m-%d %H:%M:%S %z" "$last_used" "+%s" 2>/dev/null)
        local current_epoch=$(date "+%s")
        local days_ago=$(( (current_epoch - last_used_epoch) / 86400 ))

        if [[ $days_ago -eq 0 ]]; then
            echo "Today"
        elif [[ $days_ago -eq 1 ]]; then
            echo "Yesterday"
        elif [[ $days_ago -lt 30 ]]; then
            echo "${days_ago} days ago"
        elif [[ $days_ago -lt 365 ]]; then
            local months_ago=$(( days_ago / 30 ))
            echo "${months_ago} month(s) ago"
        else
            local years_ago=$(( days_ago / 365 ))
            echo "${years_ago} year(s) ago"
        fi
    fi
}

# Scan applications and collect information
scan_applications() {
    local temp_file=$(mktemp)

    echo -n "Scanning applications... " >&2

    # Pre-cache current epoch to avoid repeated calls
    local current_epoch=$(date "+%s")

    # First pass: quickly collect all valid app paths and bundle IDs
    local -a app_data_tuples=()
    while IFS= read -r -d '' app_path; do
        if [[ ! -e "$app_path" ]]; then continue; fi

        local app_name=$(basename "$app_path" .app)

        # Quick bundle ID check first (only if plist exists)
        local bundle_id="unknown"
        if [[ -f "$app_path/Contents/Info.plist" ]]; then
            bundle_id=$(defaults read "$app_path/Contents/Info.plist" CFBundleIdentifier 2>/dev/null || echo "unknown")
        fi

        # Skip protected system apps early
        if should_preserve_bundle "$bundle_id"; then
            continue
        fi

        # Store tuple: app_path|app_name|bundle_id
        app_data_tuples+=("${app_path}|${app_name}|${bundle_id}")
    done < <(find /Applications -name "*.app" -maxdepth 1 -print0 2>/dev/null)

    # Second pass: process each app with accurate size calculation
    local app_count=0
    local total_apps=${#app_data_tuples[@]}

    for app_data_tuple in "${app_data_tuples[@]}"; do
        IFS='|' read -r app_path app_name bundle_id <<< "$app_data_tuple"

        # Show progress every few items
        ((app_count++))
        if (( app_count % 3 == 0 )) || [[ $app_count -eq $total_apps ]]; then
            echo -ne "\rScanning applications... processing $app_count/$total_apps apps" >&2
        fi

        # Accurate size calculation - this is what takes time but user wants it
        local app_size="N/A"
        if [[ -d "$app_path" ]]; then
            app_size=$(du -sh "$app_path" 2>/dev/null | cut -f1 || echo "N/A")
        fi

        # Simplified last used check using file modification time
        local last_used="Old"
        local last_used_epoch=0

        if [[ -d "$app_path" ]]; then
            last_used_epoch=$(stat -f%m "$app_path" 2>/dev/null || echo "0")
            if [[ $last_used_epoch -gt 0 ]]; then
                local days_ago=$(( (current_epoch - last_used_epoch) / 86400 ))
                if [[ $days_ago -lt 30 ]]; then
                    last_used="Recent"
                elif [[ $days_ago -lt 365 ]]; then
                    last_used="This year"
                fi
            fi
        fi

        # Format: epoch|app_path|app_name|bundle_id|size|last_used_display
        echo "${last_used_epoch}|${app_path}|${app_name}|${bundle_id}|${app_size}|${last_used}" >> "$temp_file"
    done

    echo -e "\rScanning applications... found $app_count apps ✓" >&2

    # Check if we found any applications
    if [[ ! -s "$temp_file" ]]; then
        rm -f "$temp_file"
        return 1
    fi

    # Sort by last used (oldest first) and return the temp file path
    sort -t'|' -k1,1n "$temp_file" > "${temp_file}.sorted"
    rm -f "$temp_file"
    echo "${temp_file}.sorted"
}

# Load applications into arrays
load_applications() {
    local apps_file="$1"

    if [[ ! -f "$apps_file" || ! -s "$apps_file" ]]; then
        log_warning "No applications found for uninstallation"
        return 1
    fi

    # Clear arrays
    apps_data=()
    selection_state=()

    # Read apps into array
    while IFS='|' read -r epoch app_path app_name bundle_id size last_used; do
        apps_data+=("$epoch|$app_path|$app_name|$bundle_id|$size|$last_used")
        selection_state+=(false)
    done < "$apps_file"

    if [[ ${#apps_data[@]} -eq 0 ]]; then
        log_warning "No applications available for uninstallation"
        return 1
    fi

    return 0
}

# Old display_apps function removed - replaced by new menu system

# Read a single key with proper escape sequence handling
# This function has been replaced by the menu.sh library

# Old interactive_app_selection and show_selection_help functions removed
# They have been replaced by the new menu system in lib/app_selector.sh

# Find and list app-related files
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

    printf '%s\n' "${files_to_clean[@]}"
}

# Calculate total size of files
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

# Uninstall selected applications
uninstall_applications() {
    local total_size_freed=0

    log_header "Uninstalling selected applications"

    if [[ ${#selected_apps[@]} -eq 0 ]]; then
        log_warning "No applications selected for uninstallation"
        return 0
    fi

    for selected_app in "${selected_apps[@]}"; do
        IFS='|' read -r epoch app_path app_name bundle_id size last_used <<< "$selected_app"

        echo ""
        log_info "Processing: $app_name"

        # Check if app is running
        if pgrep -f "$app_name" >/dev/null 2>&1; then
            log_warning "$app_name is currently running"
            read -p "  Force quit $app_name? (y/N): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                pkill -f "$app_name" 2>/dev/null || true
                sleep 2
            else
                log_warning "Skipping $app_name (still running)"
                continue
            fi
        fi

        # Find related files
        local related_files=$(find_app_files "$bundle_id" "$app_name")

        # Calculate total size
        local app_size_kb=$(du -sk "$app_path" 2>/dev/null | awk '{print $1}' || echo "0")
        local related_size_kb=$(calculate_total_size "$related_files")
        local total_kb=$((app_size_kb + related_size_kb))

        # Show what will be removed
        echo -e "  ${YELLOW}Files to be removed:${NC}"
        echo -e "  ${GREEN}✓${NC} Application: $(echo "$app_path" | sed "s|$HOME|~|")"

        while IFS= read -r file; do
            [[ -n "$file" && -e "$file" ]] && echo -e "  ${GREEN}✓${NC} $(echo "$file" | sed "s|$HOME|~|")"
        done <<< "$related_files"

        if [[ $total_kb -gt 1048576 ]]; then  # > 1GB
            local size_display=$(echo "$total_kb" | awk '{printf "%.2fGB", $1/1024/1024}')
        elif [[ $total_kb -gt 1024 ]]; then  # > 1MB
            local size_display=$(echo "$total_kb" | awk '{printf "%.1fMB", $1/1024}')
        else
            local size_display="${total_kb}KB"
        fi

        echo -e "  ${BLUE}Total size: $size_display${NC}"
        echo

        read -p "  Proceed with uninstalling $app_name? (y/N): " -n 1 -r
        echo

        if [[ $REPLY =~ ^[Yy]$ ]]; then
            # Remove the application
            if rm -rf "$app_path" 2>/dev/null; then
                echo -e "  ${GREEN}✓${NC} Removed application"
            else
                log_error "Failed to remove $app_path"
                continue
            fi

            # Remove related files
            while IFS= read -r file; do
                if [[ -n "$file" && -e "$file" ]]; then
                    if rm -rf "$file" 2>/dev/null; then
                        echo -e "  ${GREEN}✓${NC} Removed $(echo "$file" | sed "s|$HOME|~|" | xargs basename)"
                    fi
                fi
            done <<< "$related_files"

            ((total_size_freed += total_kb))
            ((files_cleaned++))
            ((total_items++))

            log_success "$app_name uninstalled successfully"
        else
            log_info "Skipped $app_name"
        fi
    done

    # Show final summary
    echo ""
    log_header "Uninstallation Summary"

    if [[ $total_size_freed -gt 0 ]]; then
        if [[ $total_size_freed -gt 1048576 ]]; then  # > 1GB
            local freed_display=$(echo "$total_size_freed" | awk '{printf "%.2fGB", $1/1024/1024}')
        elif [[ $total_size_freed -gt 1024 ]]; then  # > 1MB
            local freed_display=$(echo "$total_size_freed" | awk '{printf "%.1fMB", $1/1024}')
        else
            local freed_display="${total_size_freed}KB"
        fi

        log_success "Freed $freed_display of disk space"
    fi

    echo "📊 Applications uninstalled: $files_cleaned"
    ((total_size_cleaned += total_size_freed))
}

# Cleanup function - restore cursor and clean up
cleanup() {
    # Restore cursor
    printf '\033[?25h'
    exit "${1:-0}"
}

# Set trap for cleanup on exit
trap cleanup EXIT INT TERM

# Main function
main() {
    echo "🗑️  Mole - Interactive App Uninstaller"
    echo "============================================"
    echo

    # Scan applications
    local apps_file=$(scan_applications)

    if [[ ! -f "$apps_file" ]]; then
        log_error "Failed to scan applications"
        return 1
    fi

    # Load applications
    if ! load_applications "$apps_file"; then
        rm -f "$apps_file"
        return 1
    fi

    # Interactive selection using new menu system
    if ! select_apps_for_uninstall; then
        rm -f "$apps_file"
        return 0
    fi

    # Restore cursor for normal interaction
    printf '\033[?25h'
    clear
    echo "You selected ${#selected_apps[@]} application(s) for uninstallation:"
    echo ""

    if [[ ${#selected_apps[@]} -gt 0 ]]; then
        for selected_app in "${selected_apps[@]}"; do
            IFS='|' read -r epoch app_path app_name bundle_id size last_used <<< "$selected_app"
            echo "  • $app_name ($size)"
        done
    else
        echo "  No applications to uninstall."
    fi

    echo ""
    # 直接执行批量卸载，确认已在批量卸载函数中处理
    batch_uninstall_applications

    # Cleanup
    rm -f "$apps_file"

    log_success "App uninstaller finished"
}

# Run main function
main "$@"
