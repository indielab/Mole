#!/bin/bash

# App selection functionality using the new menu system
# This replaces the complex interactive_app_selection function

# Interactive app selection using the menu.sh library
select_apps_for_uninstall() {
    if [[ ${#apps_data[@]} -eq 0 ]]; then
        log_warning "No applications available for uninstallation"
        return 1
    fi

    # Build menu options from apps_data
    local -a menu_options=()
    for app_data in "${apps_data[@]}"; do
        IFS='|' read -r epoch app_path app_name bundle_id size last_used <<< "$app_data"

        # The size is already formatted (e.g., "91M", "2.1G"), so use it directly
        local size_str="Unknown"
        if [[ "$size" != "0" && "$size" != "" && "$size" != "Unknown" ]]; then
            size_str="$size"
        fi

        # Format display name with better width control
        local display_name
        local max_name_length=25
        local truncated_name="$app_name"

        # Truncate app name if too long
        if [[ ${#app_name} -gt $max_name_length ]]; then
            truncated_name="${app_name:0:$((max_name_length-3))}..."
        fi

        # Create aligned display format
        display_name=$(printf "%-${max_name_length}s %8s | %s" "$truncated_name" "($size_str)" "$last_used")
        menu_options+=("$display_name")
    done

    echo ""
    echo "🗑️ App Uninstaller"
    echo ""
    echo "Found ${#apps_data[@]} apps. Select apps to remove:"
    echo ""

    # Load paginated menu system (arrow key navigation)
    source "$(dirname "${BASH_SOURCE[0]}")/paginated_menu.sh"

    # Use paginated multi-select menu with arrow key navigation
    local selected_indices
    selected_indices=$(paginated_multi_select "Select Apps to Remove" "${menu_options[@]}")
    local exit_code=$?

    if [[ $exit_code -ne 0 ]]; then
        echo "Cancelled"
        return 1
    fi

    if [[ -z "$selected_indices" ]]; then
        echo "No apps selected"
        return 1
    fi

    # Build selected_apps array from indices
    selected_apps=()
    for idx in $selected_indices; do
        # Validate that idx is a number
        if [[ "$idx" =~ ^[0-9]+$ ]]; then
            selected_apps+=("${apps_data[idx]}")
        fi
    done

    echo "Selected ${#selected_apps[@]} apps"
    return 0
}

# Alternative simplified single-select interface for quick selection
quick_select_app() {
    if [[ ${#apps_data[@]} -eq 0 ]]; then
        log_warning "No applications available for uninstallation"
        return 1
    fi

    # Build menu options from apps_data (same as above)
    local -a menu_options=()
    for app_data in "${apps_data[@]}"; do
        IFS='|' read -r epoch app_path app_name bundle_id size last_used <<< "$app_data"

        # The size is already formatted (e.g., "91M", "2.1G"), so use it directly
        local size_str="Unknown"
        if [[ "$size" != "0" && "$size" != "" && "$size" != "Unknown" ]]; then
            size_str="$size"
        fi

        # Format display name with better width control
        local display_name
        local max_name_length=25
        local truncated_name="$app_name"

        # Truncate app name if too long
        if [[ ${#app_name} -gt $max_name_length ]]; then
            truncated_name="${app_name:0:$((max_name_length-3))}..."
        fi

        # Create aligned display format
        display_name=$(printf "%-${max_name_length}s %8s | %s" "$truncated_name" "($size_str)" "$last_used")
        menu_options+=("$display_name")
    done

    echo ""
    echo "🗑️ Quick Uninstall"
    echo ""

    # Use single-select menu
    if show_menu "Quick Uninstall" "${menu_options[@]}"; then
        local selected_idx=$?
        selected_apps=("${apps_data[selected_idx]}")
        echo "✅ Selected: ${menu_options[selected_idx]}"
        return 0
    else
        echo "❌ Operation cancelled"
        return 1
    fi
}

# Show app selection mode menu
show_app_selection_mode() {
    echo ""
    echo "🗑️ Application Uninstaller"
    echo ""

    local mode_options=(
        "Batch Mode (select multiple apps with checkboxes)"
        "Quick Mode (select one app at a time)"
        "Exit Uninstaller"
    )

    if show_menu "Choose uninstall mode:" "${mode_options[@]}"; then
        local mode=$?
        case $mode in
            0)
                select_apps_for_uninstall
                return $?
                ;;
            1)
                quick_select_app
                return $?
                ;;
            2)
                echo "Goodbye!"
                return 1
                ;;
        esac
    else
        echo "Operation cancelled"
        return 1
    fi
}