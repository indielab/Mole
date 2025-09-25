#!/bin/bash

# Smart menu with pagination and search for large lists
# Much better UX for handling many items

# Smart multi-select with search and pagination
smart_multi_select() {
    local title="$1"
    shift
    local -a all_items=("$@")

    if [[ ${#all_items[@]} -eq 0 ]]; then
        echo "Error: No items provided" >&2
        return 1
    fi

    local -a selected_indices=()
    local -a filtered_items=()
    local -a filtered_indices=()
    local search_term=""
    local page_size=15
    local current_page=0

    # Function to filter items based on search
    filter_items() {
        filtered_items=()
        filtered_indices=()

        if [[ -z "$search_term" ]]; then
            # No search, show all items
            filtered_items=("${all_items[@]}")
            for ((i = 0; i < ${#all_items[@]}; i++)); do
                filtered_indices+=($i)
            done
        else
            # Filter items that contain search term (case insensitive)
            for ((i = 0; i < ${#all_items[@]}; i++)); do
                if [[ "${all_items[i],,}" == *"${search_term,,}"* ]]; then
                    filtered_items+=("${all_items[i]}")
                    filtered_indices+=($i)
                fi
            done
        fi
    }

    # Function to display current page
    show_page() {
        local total_filtered=${#filtered_items[@]}
        local total_pages=$(( (total_filtered + page_size - 1) / page_size ))
        local start_idx=$((current_page * page_size))
        local end_idx=$((start_idx + page_size - 1))

        if [[ $end_idx -ge $total_filtered ]]; then
            end_idx=$((total_filtered - 1))
        fi

        printf '\033[2J\033[H' >&2
        echo "╭─────────────────────────────────────────────────────╮" >&2
        echo "│                   $title" >&2
        echo "├─────────────────────────────────────────────────────┤" >&2
        echo "│ Total: ${#all_items[@]} | Filtered: $total_filtered | Selected: ${#selected_indices[@]} │" >&2

        if [[ -n "$search_term" ]]; then
            echo "│ Search: '$search_term'                                 │" >&2
        fi

        if [[ $total_pages -gt 1 ]]; then
            echo "│ Page $(($current_page + 1)) of $total_pages                                        │" >&2
        fi
        echo "╰─────────────────────────────────────────────────────╯" >&2
        echo "" >&2

        if [[ $total_filtered -eq 0 ]]; then
            echo "No items match your search." >&2
            echo "" >&2
        else
            # Show items for current page
            for ((i = start_idx; i <= end_idx && i < total_filtered; i++)); do
                local item_idx=${filtered_indices[i]}
                local display_num=$((i + 1))

                # Check if this item is selected
                local is_selected=false
                if [[ ${#selected_indices[@]} -gt 0 ]]; then
                    for selected in "${selected_indices[@]}"; do
                        if [[ $selected -eq $item_idx ]]; then
                            is_selected=true
                            break
                        fi
                    done
                fi

                if [[ $is_selected == true ]]; then
                    printf "%3d) ✓ %s\n" "$display_num" "${filtered_items[i]}" >&2
                else
                    printf "%3d)   %s\n" "$display_num" "${filtered_items[i]}" >&2
                fi
            done
        fi

        echo "" >&2
        echo "Commands:" >&2
        echo "  Numbers: Select items (e.g., '1-5', '1 3 7', '10-15')" >&2
        echo "  /search: Filter items (e.g., '/chrome')" >&2
        echo "  n/p: Next/Previous page | all: Select all | none: Clear all" >&2
        echo "  done: Finish selection | quit: Cancel" >&2
        echo "" >&2
    }

    # Main loop
    while true; do
        filter_items
        show_page

        read -p "Enter command: " -r input >&2

        case "$input" in
            "done"|"")
                break
                ;;
            "quit"|"q")
                return 1
                ;;
            "all")
                selected_indices=()
                for idx in "${filtered_indices[@]}"; do
                    selected_indices+=($idx)
                done
                echo "Selected all filtered items (${#filtered_indices[@]})" >&2
                ;;
            "none")
                selected_indices=()
                echo "Cleared all selections" >&2
                ;;
            "n"|"next")
                local total_pages=$(( (${#filtered_items[@]} + page_size - 1) / page_size ))
                if [[ $((current_page + 1)) -lt $total_pages ]]; then
                    ((current_page++))
                else
                    echo "Already on last page" >&2
                fi
                ;;
            "p"|"prev")
                if [[ $current_page -gt 0 ]]; then
                    ((current_page--))
                else
                    echo "Already on first page" >&2
                fi
                ;;
            /*)
                # Search functionality
                search_term="${input#/}"
                current_page=0
                echo "Searching for: '$search_term'" >&2
                ;;
            *)
                # Parse selection input
                parse_selection "$input"
                ;;
        esac

        [[ "$input" != "n" && "$input" != "next" && "$input" != "p" && "$input" != "prev" ]] && sleep 1
    done

    # Return selected indices
    local result=""
    if [[ ${#selected_indices[@]} -gt 0 ]]; then
        for idx in "${selected_indices[@]}"; do
            result="$result $idx"
        done
        echo "${result# }"
    else
        echo ""
    fi
    return 0
}

# Parse selection input (supports ranges and individual numbers)
parse_selection() {
    local input="$1"
    local start_idx=$((current_page * page_size))

    # Split input by spaces
    read -ra parts <<< "$input"

    for part in "${parts[@]}"; do
        if [[ "$part" =~ ^[0-9]+$ ]]; then
            # Single number
            local display_num=$part
            local array_idx=$((display_num - 1))

            if [[ $array_idx -ge 0 && $array_idx -lt ${#filtered_items[@]} ]]; then
                local real_idx=${filtered_indices[array_idx]}
                toggle_selection "$real_idx"
            else
                echo "Invalid selection: $part (range: 1-${#filtered_items[@]})" >&2
            fi

        elif [[ "$part" =~ ^([0-9]+)-([0-9]+)$ ]]; then
            # Range like 1-5
            local start_num=${BASH_REMATCH[1]}
            local end_num=${BASH_REMATCH[2]}

            for ((num = start_num; num <= end_num; num++)); do
                local array_idx=$((num - 1))
                if [[ $array_idx -ge 0 && $array_idx -lt ${#filtered_items[@]} ]]; then
                    local real_idx=${filtered_indices[array_idx]}
                    toggle_selection "$real_idx"
                fi
            done

        else
            echo "Invalid format: $part (use numbers, ranges like '1-5', or commands)" >&2
        fi
    done
}

# Toggle selection of an item
toggle_selection() {
    local idx=$1
    local already_selected=false
    local pos_to_remove=-1

    # Check if already selected
    if [[ ${#selected_indices[@]} -gt 0 ]]; then
        for ((i = 0; i < ${#selected_indices[@]}; i++)); do
            if [[ ${selected_indices[i]} -eq $idx ]]; then
                already_selected=true
                pos_to_remove=$i
                break
            fi
        done
    fi

    if [[ $already_selected == true ]]; then
        # Remove from selection
        unset selected_indices[$pos_to_remove]
        selected_indices=("${selected_indices[@]}")  # Reindex array
        echo "Removed: ${all_items[idx]}" >&2
    else
        # Add to selection
        selected_indices+=($idx)
        echo "Added: ${all_items[idx]}" >&2
    fi
}

# Demo function
demo_smart() {
    local test_apps=()
    for i in {1..50}; do
        test_apps+=("Test App $i (${RANDOM}MB)")
    done

    echo "=== Smart Multi-select Demo ===" >&2
    local result
    result=$(smart_multi_select "Choose Applications to Remove" "${test_apps[@]}")
    if [[ $? -eq 0 ]]; then
        echo "You selected indices: '$result'" >&2
        echo "Selected ${result// /,} out of ${#test_apps[@]} items" >&2
    else
        echo "Selection cancelled" >&2
    fi
}

# Run demo if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    demo_smart
fi