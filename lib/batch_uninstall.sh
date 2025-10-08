#!/bin/bash

set -euo pipefail

# Ensure common.sh is loaded
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[[ -z "${MOLE_COMMON_LOADED:-}" ]] && source "$SCRIPT_DIR/lib/common.sh"

# Batch uninstall functionality with minimal confirmations
# Replaces the overly verbose individual confirmation approach
# Note: find_app_files() and calculate_total_size() functions now in lib/common.sh

# Batch uninstall with single confirmation
batch_uninstall_applications() {
    local total_size_freed=0

    if [[ ${#selected_apps[@]} -eq 0 ]]; then
        log_warning "No applications selected for uninstallation"
        return 0
    fi

    # Pre-process: Check for running apps and calculate total impact
    local -a running_apps=()
    local -a sudo_apps=()
    local total_estimated_size=0
    local -a app_details=()

    echo ""
    # Silent analysis without spinner output (avoid visual flicker)
    for selected_app in "${selected_apps[@]}"; do
        [[ -z "$selected_app" ]] && continue
        IFS='|' read -r epoch app_path app_name bundle_id size last_used <<< "$selected_app"

        # Check if app is running
        if pgrep -f "$app_name" >/dev/null 2>&1; then
            running_apps+=("$app_name")
        fi

        # Check if app requires sudo to delete
        if [[ ! -w "$(dirname "$app_path")" ]] || [[ "$(stat -f%Su "$app_path" 2>/dev/null)" == "root" ]]; then
            sudo_apps+=("$app_name")
        fi

        # Calculate size for summary
        local app_size_kb=$(du -sk "$app_path" 2>/dev/null | awk '{print $1}' || echo "0")
        local related_files=$(find_app_files "$bundle_id" "$app_name")
        local related_size_kb=$(calculate_total_size "$related_files")
        local total_kb=$((app_size_kb + related_size_kb))
        ((total_estimated_size += total_kb))

        # Store details for later use
        # Base64 encode related_files to handle multi-line data safely
        local encoded_files=$(echo "$related_files" | base64)
        app_details+=("$app_name|$app_path|$bundle_id|$total_kb|$encoded_files")
    done

    # Format size display (convert KB to bytes for bytes_to_human())
    local size_display=$(bytes_to_human "$((total_estimated_size * 1024))")

    # Request sudo access if needed (do this before confirmation)
    if [[ ${#sudo_apps[@]} -gt 0 ]]; then
        # Check if sudo is already cached
        if sudo -n true 2>/dev/null; then
            echo "◎ Admin access confirmed for: ${sudo_apps[*]}"
        else
            echo "◎ Admin required for: ${sudo_apps[*]}"
            echo ""
            if ! request_sudo_access "Uninstalling system apps requires admin access"; then
                echo ""
                log_error "Admin access denied"
                return 1
            fi
            echo ""
            echo "✓ Admin access granted"
        fi
        echo "◎ Gathering targets..."
        (while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null) &
        local sudo_keepalive_pid=$!
        local _trap_cleanup_cmd="kill $sudo_keepalive_pid 2>/dev/null || true; wait $sudo_keepalive_pid 2>/dev/null || true"
        for signal in EXIT INT TERM; do
            local existing_trap; existing_trap=$(trap -p "$signal" | awk -F"'" '{print $2}')
            if [[ -n "$existing_trap" ]]; then
                trap "$existing_trap; $_trap_cleanup_cmd" "$signal"
            else
                trap "$_trap_cleanup_cmd" "$signal"
            fi
        done
    fi

    # Show summary and get batch confirmation
    local app_total=${#selected_apps[@]}
    if [[ ${#running_apps[@]} -gt 0 ]]; then
        echo -n "${BLUE}◎ Remove ${app_total} app(s) (${size_display}) | Quit: ${running_apps[*]} | Enter=go / ESC=q:${NC} "
    else
        echo -n "${BLUE}◎ Remove ${app_total} app(s) (${size_display}) | Enter=go / ESC=q:${NC} "
    fi
    IFS= read -r -s -n1 key || key=""
    case "$key" in
        $'\e'|q|Q) echo ""; return 0 ;;
        ""|$'\n'|$'\r'|y|Y) echo "" ;;
        *) echo ""; return 0 ;;
    esac

    echo -n "◎ Starting in 3s... 3"; sleep 1; echo -ne "\r◎ Starting in 3s... 2"; sleep 1; echo -ne "\r◎ Starting in 3s... 1"; sleep 1
    echo -ne "\r\033[K"
    if [[ -t 1 ]]; then start_inline_spinner "Uninstalling apps..."; fi

    # Force quit running apps first (batch)
    if [[ ${#running_apps[@]} -gt 0 ]]; then
        pkill -f "${running_apps[0]}" 2>/dev/null || true
        for app_name in "${running_apps[@]:1}"; do pkill -f "$app_name" 2>/dev/null || true; done
        sleep 2
        if pgrep -f "${running_apps[0]}" >/dev/null 2>&1; then sleep 1; fi
    fi

    # Perform uninstallations (compact output)
    if [[ -t 1 ]]; then stop_inline_spinner; fi
    echo ""
    local success_count=0 failed_count=0
    local -a failed_items=()
    for detail in "${app_details[@]}"; do
        IFS='|' read -r app_name app_path bundle_id total_kb encoded_files <<< "$detail"
        local related_files=$(echo "$encoded_files" | base64 -d)
        local reason=""
        local needs_sudo=false
        [[ ! -w "$(dirname "$app_path")" || "$(stat -f%Su "$app_path" 2>/dev/null)" == "root" ]] && needs_sudo=true
        if ! force_kill_app "$app_name"; then
            reason="still running"
        fi
        if [[ -z "$reason" ]]; then
            if [[ "$needs_sudo" == true ]]; then
                sudo rm -rf "$app_path" 2>/dev/null || reason="remove failed"
            else
                rm -rf "$app_path" 2>/dev/null || reason="remove failed"
            fi
        fi
        if [[ -z "$reason" ]]; then
            local files_removed=0
            while IFS= read -r file; do
                [[ -n "$file" && -e "$file" ]] || continue
                rm -rf "$file" 2>/dev/null && ((files_removed++)) || true
            done <<< "$related_files"
            ((total_size_freed += total_kb))
            ((success_count++))
            ((files_cleaned++))
            ((total_items++))
            printf "  ${GREEN}OK${NC}   %-20s%s\n" "$app_name" $([[ $files_removed -gt 0 ]] && echo "+$files_removed" )
        else
            ((failed_count++))
            failed_items+=("$app_name:$reason")
        fi
    done

    # Summary
    local freed_display="0B"
    if [[ $total_size_freed -gt 0 ]]; then
        local freed_kb=$total_size_freed
        if [[ $freed_kb -ge 1048576 ]]; then
            freed_display=$(echo "$freed_kb" | awk '{printf "%.2fGB", $1/1024/1024}')
        elif [[ $freed_kb -ge 1024 ]]; then
            freed_display=$(echo "$freed_kb" | awk '{printf "%.1fMB", $1/1024}')
        else
            freed_display="${freed_kb}KB"
        fi
    fi
    local bar="================================================================================"
    echo ""
    echo "$bar"
    if [[ $failed_count -gt 0 ]]; then
        echo -e "Removed: ${GREEN}$success_count${NC} | Failed: ${RED}$failed_count${NC} | Freed: ${GREEN}$freed_display${NC}"
        if [[ $failed_count -eq 1 ]]; then
            local first="${failed_items[0]}"
            local name=${first%%:*}
            local reason=${first#*:}
            echo "${name} $(map_uninstall_reason "$reason")"
        else
            local joined="${failed_items[*]}"; echo "Failures: $joined"
        fi
    else
        echo -e "Removed: ${GREEN}$success_count${NC} | Failed: ${RED}$failed_count${NC} | Freed: ${GREEN}$freed_display${NC}"
    fi
    echo "$bar"

    # Clean up sudo keepalive if it was started
    if [[ -n "${sudo_keepalive_pid:-}" ]]; then
        kill "$sudo_keepalive_pid" 2>/dev/null || true
        wait "$sudo_keepalive_pid" 2>/dev/null || true
    fi

    ((total_size_cleaned += total_size_freed))
    unset failed_items
}
