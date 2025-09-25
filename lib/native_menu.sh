#!/bin/bash

# Simple native bash menu using the built-in select command
# This is the most reliable approach with zero dependencies

# Multi-select using native bash select with checkboxes simulation
multi_select_native() {
    local title="$1"
    shift
    local -a items=("$@")

    if [[ ${#items[@]} -eq 0 ]]; then
        echo "Error: No items provided" >&2
        return 1
    fi

    echo "=== $title ===" >&2
    echo "Select multiple items (enter numbers separated by spaces, or 'done' when finished):" >&2
    echo "" >&2

    # Display items with numbers
    for ((i = 0; i < ${#items[@]}; i++)); do
        printf "%2d) %s\n" $((i + 1)) "${items[i]}" >&2
    done
    echo "" >&2

    local -a selected_indices=()

    while true; do
        echo "Currently selected: ${#selected_indices[@]} items" >&2
        if [[ ${#selected_indices[@]} -gt 0 ]]; then
            echo "Selected indices: ${selected_indices[*]}" >&2
        fi
        echo "" >&2

        read -p "Enter selection (numbers, 'all', 'none', or 'done'): " -r input >&2

        case "$input" in
            "done"|"")
                break
                ;;
            "all")
                selected_indices=()
                for ((i = 0; i < ${#items[@]}; i++)); do
                    selected_indices+=($i)
                done
                echo "Selected all ${#items[@]} items" >&2
                ;;
            "none")
                selected_indices=()
                echo "Cleared all selections" >&2
                ;;
            *)
                # Parse space-separated numbers
                read -ra nums <<< "$input"
                for num in "${nums[@]}"; do
                    if [[ "$num" =~ ^[0-9]+$ ]] && [[ $num -ge 1 ]] && [[ $num -le ${#items[@]} ]]; then
                        local idx=$((num - 1))
                        # Check if already selected
                        local already_selected=false
                        if [[ ${#selected_indices[@]} -gt 0 ]]; then
                            for selected in "${selected_indices[@]}"; do
                                if [[ $selected -eq $idx ]]; then
                                    already_selected=true
                                    break
                                fi
                            done
                        fi

                        if [[ $already_selected == false ]]; then
                            selected_indices+=($idx)
                            echo "Added: ${items[idx]}" >&2
                        else
                            echo "Already selected: ${items[idx]}" >&2
                        fi
                    else
                        echo "Invalid selection: $num (must be 1-${#items[@]})" >&2
                    fi
                done
                ;;
        esac
        echo "" >&2
    done

    # Convert to space-separated string and return
    local result=""
    if [[ ${#selected_indices[@]} -gt 0 ]]; then
        for idx in "${selected_indices[@]}"; do
            result="$result $idx"
        done
        echo "${result# }"  # Remove leading space
    else
        echo ""  # Return empty string for no selections
    fi
    return 0
}

# Simple single-select using native bash select
single_select_native() {
    local title="$1"
    shift
    local -a items=("$@")

    if [[ ${#items[@]} -eq 0 ]]; then
        echo "Error: No items provided" >&2
        return 1
    fi

    echo "=== $title ===" >&2

    # Use PS3 to customize the select prompt
    local PS3="Please select an option (1-${#items[@]}): "

    select item in "${items[@]}" "Cancel"; do
        if [[ -n "$item" ]]; then
            if [[ "$item" == "Cancel" ]]; then
                return 1
            else
                # Find the index of selected item
                for ((i = 0; i < ${#items[@]}; i++)); do
                    if [[ "${items[i]}" == "$item" ]]; then
                        echo "$i"
                        return 0
                    fi
                done
            fi
        else
            echo "Invalid selection. Please try again." >&2
        fi
    done 2>&2  # Redirect select dialog to stderr
}

# Demo function
demo_native() {
    echo "=== Multi-select Demo ===" >&2
    local result
    result=$(multi_select_native "Choose Applications" "App 1" "App 2" "App 3" "App 4" "App 5")
    if [[ $? -eq 0 ]]; then
        echo "You selected indices: '$result'" >&2
    else
        echo "Selection cancelled" >&2
    fi

    echo "" >&2
    echo "=== Single-select Demo ===" >&2
    result=$(single_select_native "Choose One App" "Option A" "Option B" "Option C")
    if [[ $? -eq 0 ]]; then
        echo "You selected index: $result" >&2
    else
        echo "Selection cancelled" >&2
    fi
}

# Run demo if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    demo_native
fi