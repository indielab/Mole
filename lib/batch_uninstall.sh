#!/bin/bash

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
        # Base64 encode related_files to handle multi-line data safely
        local encoded_files=$(echo "$related_files" | base64)
        app_details+=("$app_name|$app_path|$bundle_id|$total_kb|$encoded_files")
    done

    # Format size display
    if [[ $total_estimated_size -gt 1048576 ]]; then
        local size_display=$(echo "$total_estimated_size" | awk '{printf "%.2fGB", $1/1024/1024}')
    elif [[ $total_estimated_size -gt 1024 ]]; then
        local size_display=$(echo "$total_estimated_size" | awk '{printf "%.1fMB", $1/1024}')
    else
        local size_display="${total_estimated_size}KB"
    fi

    # Show summary and get batch confirmation
    echo ""
    echo "Will remove ${#selected_apps[@]} applications, free $size_display"
    if [[ ${#running_apps[@]} -gt 0 ]]; then
        echo "Running apps will be force-quit: ${running_apps[*]}"
    fi
    echo ""
    read -p "Press ENTER to confirm, or any other key to cancel: " -r

    if [[ -n "$REPLY" ]]; then
        log_info "Uninstallation cancelled by user"
        return 0
    fi

    echo "⚡ Starting uninstallation in 3 seconds... (Press Ctrl+C to abort)"
    sleep 1 && echo "⚡ 2..."
    sleep 1 && echo "⚡ 1..."
    sleep 1

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
        IFS='|' read -r app_name app_path bundle_id total_kb encoded_files <<< "$detail"

        # Decode the related files list
        local related_files=$(echo "$encoded_files" | base64 -d)

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
    echo "===================================================================="
    echo "🎉 UNINSTALLATION COMPLETE!"
    
    if [[ $success_count -gt 0 ]]; then
        if [[ $total_size_freed -gt 1048576 ]]; then
            local freed_display=$(echo "$total_size_freed" | awk '{printf "%.1fGB", $1/1024/1024}')
        elif [[ $total_size_freed -gt 1024 ]]; then
            local freed_display=$(echo "$total_size_freed" | awk '{printf "%.1fMB", $1/1024}')
        else
            local freed_display="${total_size_freed}KB"
        fi
        echo "🗑️  Apps uninstalled: $success_count | Space freed: $freed_display"
    else
        echo "🗑️  No applications were uninstalled"
    fi
    
    if [[ $failed_count -gt 0 ]]; then
        echo "⚠️  Failed to uninstall: $failed_count"
    fi
    
    echo "===================================================================="
    if [[ $failed_count -gt 0 ]]; then
        log_warning "$failed_count applications failed to uninstall"
    fi

    ((total_size_cleaned += total_size_freed))
}