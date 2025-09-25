#!/bin/bash

# Batch uninstall functionality with minimal confirmations
# Replaces the overly verbose individual confirmation approach

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

# Batch uninstall with single confirmation
batch_uninstall_applications() {
    local total_size_freed=0

    if [[ ${#selected_apps[@]} -eq 0 ]]; then
        log_warning "No applications selected for uninstallation"
        return 0
    fi

    # Pre-process: Check for running apps and calculate total impact
    local -a running_apps=()
    local total_estimated_size=0
    local -a app_details=()

    echo "📋 Analyzing selected applications..."
    for selected_app in "${selected_apps[@]}"; do
        IFS='|' read -r epoch app_path app_name bundle_id size last_used <<< "$selected_app"

        # Check if app is running
        if pgrep -f "$app_name" >/dev/null 2>&1; then
            running_apps+=("$app_name")
        fi

        # Calculate size for summary
        local app_size_kb=$(du -sk "$app_path" 2>/dev/null | awk '{print $1}' || echo "0")
        local related_files=$(find_app_files "$bundle_id" "$app_name")
        local related_size_kb=$(calculate_total_size "$related_files")
        local total_kb=$((app_size_kb + related_size_kb))
        ((total_estimated_size += total_kb))

        # Store details for later use
        app_details+=("$app_name|$app_path|$bundle_id|$total_kb|$related_files")
    done

    # Show summary and get batch confirmation
    echo ""
    echo "📊 Uninstallation Summary:"
    echo "  • Applications to remove: ${#selected_apps[@]}"

    if [[ $total_estimated_size -gt 1048576 ]]; then
        local size_display=$(echo "$total_estimated_size" | awk '{printf "%.2fGB", $1/1024/1024}')
    elif [[ $total_estimated_size -gt 1024 ]]; then
        local size_display=$(echo "$total_estimated_size" | awk '{printf "%.1fMB", $1/1024}')
    else
        local size_display="${total_estimated_size}KB"
    fi
    echo "  • Estimated space to free: $size_display"

    if [[ ${#running_apps[@]} -gt 0 ]]; then
        echo "  • ⚠️  Running apps that will be force-quit:"
        for app in "${running_apps[@]}"; do
            echo "    - $app"
        done
    fi

    echo ""
    echo "Selected applications:"
    for selected_app in "${selected_apps[@]}"; do
        IFS='|' read -r epoch app_path app_name bundle_id size last_used <<< "$selected_app"
        echo "  • $app_name ($size)"
    done

    echo ""
    read -p "🗑️  Proceed with uninstalling ALL ${#selected_apps[@]} applications? This cannot be undone. (Y/n): " -n 1 -r
    echo

    if [[ $REPLY =~ ^[Nn]$ ]]; then
        log_info "Uninstallation cancelled by user"
        return 0
    fi

    # Force quit running apps first (batch)
    if [[ ${#running_apps[@]} -gt 0 ]]; then
        echo ""
        log_info "Force quitting running applications..."
        for app_name in "${running_apps[@]}"; do
            echo "  • Quitting $app_name..."
            pkill -f "$app_name" 2>/dev/null || true
        done
        echo "  • Waiting 3 seconds for apps to close..."
        sleep 3
    fi

    # Perform uninstallations without individual confirmations
    echo ""
    log_info "Starting batch uninstallation..."
    local success_count=0
    local failed_count=0

    for detail in "${app_details[@]}"; do
        IFS='|' read -r app_name app_path bundle_id total_kb related_files <<< "$detail"

        echo ""
        echo "🗑️  Uninstalling: $app_name"

        # Remove the application
        if rm -rf "$app_path" 2>/dev/null; then
            echo -e "  ${GREEN}✓${NC} Removed application"

            # Remove related files
            local files_removed=0
            while IFS= read -r file; do
                if [[ -n "$file" && -e "$file" ]]; then
                    if rm -rf "$file" 2>/dev/null; then
                        ((files_removed++))
                    fi
                fi
            done <<< "$related_files"

            if [[ $files_removed -gt 0 ]]; then
                echo -e "  ${GREEN}✓${NC} Cleaned $files_removed related files"
            fi

            ((total_size_freed += total_kb))
            ((success_count++))
            ((files_cleaned++))
            ((total_items++))

        else
            echo -e "  ${RED}✗${NC} Failed to remove $app_name"
            ((failed_count++))
        fi
    done

    # Show final summary
    echo ""
    log_header "Uninstallation Complete"

    if [[ $success_count -gt 0 ]]; then
        if [[ $total_size_freed -gt 1048576 ]]; then
            local freed_display=$(echo "$total_size_freed" | awk '{printf "%.2fGB", $1/1024/1024}')
        elif [[ $total_size_freed -gt 1024 ]]; then
            local freed_display=$(echo "$total_size_freed" | awk '{printf "%.1fMB", $1/1024}')
        else
            local freed_display="${total_size_freed}KB"
        fi
        log_success "Successfully uninstalled $success_count applications"
        log_success "Freed $freed_display of disk space"
    fi

    if [[ $failed_count -gt 0 ]]; then
        log_warning "$failed_count applications failed to uninstall"
    fi

    ((total_size_cleaned += total_size_freed))
}