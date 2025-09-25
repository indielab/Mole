#!/bin/bash

# Proper paginated menu with arrow key navigation
# 10 items per page, up/down to navigate, space to select, left/right to change pages

# Terminal control functions
hide_cursor() { printf '\033[?25l' >&2; }
show_cursor() { printf '\033[?25h' >&2; }
clear_screen() { printf '\033[2J\033[H' >&2; }
enter_alt_screen() { tput smcup >/dev/null 2>&1 || true; }
leave_alt_screen() { tput rmcup >/dev/null 2>&1 || true; }
disable_wrap() { printf '\033[?7l' >&2; }   # disable line wrap
enable_wrap() { printf '\033[?7h' >&2; }

# Read single key with arrow key support (macOS bash 3.2 friendly)
read_key() {
    local key seq
    IFS= read -rsn1 key || return 1

    # Some terminals may yield empty on Enter with -n1
    if [[ -z "$key" ]]; then
        echo "ENTER"
        return 0
    fi

    case "$key" in
        $'\033')
            # Read next two bytes within 1s: "[A", "[B", ...
            if IFS= read -rsn2 -t 1 seq 2>/dev/null; then
                case "$seq" in
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
        ' ') echo "SPACE" ;;
        $'\n'|$'\r') echo "ENTER" ;;
        'q'|'Q') echo "QUIT" ;;
        'a'|'A') echo "ALL" ;;
        'n'|'N') echo "NONE" ;;
        '?') echo "HELP" ;;
        *) echo "OTHER" ;;
    esac
}

# Paginated multi-select menu
paginated_multi_select() {
    local title="$1"
    shift
    local -a items=("$@")

    local total_items=${#items[@]}
    local items_per_page=10  # Reduced for better readability
    local total_pages=$(( (total_items + items_per_page - 1) / items_per_page ))
    local current_page=0
    local cursor_pos=0  # Position within current page (0-9)
    local -a selected=()

    # Initialize selection array
    for ((i = 0; i < total_items; i++)); do
        selected[i]=false
    done

    # Cleanup function
    cleanup() {
        show_cursor
        stty echo 2>/dev/null || true
        stty icanon 2>/dev/null || true
        leave_alt_screen
        enable_wrap
    }
    trap cleanup EXIT INT TERM

    # Setup terminal for optimal responsiveness
    stty -echo -icanon min 1 time 0 2>/dev/null || true
    enter_alt_screen
    disable_wrap
    hide_cursor

    # Main display function
    first_draw=1
    # Helper: print one cleared line
    print_line() {
        printf "\r\033[2K%s\n" "$1" >&2
    }

    # Helper: render one item line at given page position
    render_item_line() {
        local page_pos=$1
        local start_idx=$((current_page * items_per_page))
        local i=$((start_idx + page_pos))
        local checkbox="☐"
        local cursor_marker="  "
        [[ ${selected[i]} == true ]] && checkbox="☑"
        if [[ $page_pos -eq $cursor_pos ]]; then
            cursor_marker="▶ "
            printf "\r\033[2K\033[7m%s%s %s\033[0m\n" "$cursor_marker" "$checkbox" "${items[i]}" >&2
        else
            printf "\r\033[2K%s%s %s\n" "$cursor_marker" "$checkbox" "${items[i]}" >&2
        fi
    }

    # Helper: move cursor to top-left anchor saved by tput sc
    to_anchor() { tput rc >/dev/null 2>&1 || true; }

    # Full draw of entire screen - simplified for stability
    draw_menu() {
        # Always do full screen redraw for reliability
        clear_screen

        # Simple header
        printf "%s\n" "$title" >&2
        printf "%s\n" "$(printf '=%.0s' $(seq 1 ${#title}))" >&2

        # Status bar
        local selected_count=0
        for ((i = 0; i < total_items; i++)); do
            [[ ${selected[i]} == true ]] && ((selected_count++))
        done

        printf "Page %d/%d │ Total: %d │ Selected: %d\n" \
            $((current_page + 1)) $total_pages $total_items $selected_count >&2
        print_line ""

        # Calculate page boundaries
        local start_idx=$((current_page * items_per_page))
        local end_idx=$((start_idx + items_per_page - 1))
        [[ $end_idx -ge $total_items ]] && end_idx=$((total_items - 1))

        # Display items for current page
        for ((i = start_idx; i <= end_idx; i++)); do
            local page_pos=$((i - start_idx))
            render_item_line "$page_pos"
        done

        # Fill empty slots to always print items_per_page lines
        local items_on_page=$((end_idx - start_idx + 1))
        for ((i = items_on_page; i < items_per_page; i++)); do
            print_line ""
        done

        print_line ""
        print_line "↑↓: Navigate | Space: Select | Enter: Confirm | Q: Exit"
    }

    # Help screen
    show_help() {
        clear_screen
        echo "App Uninstaller - Help" >&2
        echo "======================" >&2
        echo >&2
        echo "  ↑ / ↓       Navigate up/down" >&2
        echo "  ← / →       Previous/next page" >&2
        echo "  Space       Select/deselect app" >&2
        echo "  Enter       Confirm selection" >&2
        echo "  A           Select all" >&2
        echo "  N           Deselect all" >&2
        echo "  Q           Exit" >&2
        echo >&2
        read -p "Press any key to continue..." -n 1 >&2
    }

    # Main loop - simplified to always do full redraws for stability
    while true; do
        draw_menu  # Always full redraw to avoid display issues

        local key=$(read_key)

        # Immediate exit key
        if [[ "$key" == "QUIT" ]]; then
            cleanup
            return 1
        fi

        case "$key" in
            "UP")
                if [[ $cursor_pos -gt 0 ]]; then
                    ((cursor_pos--))
                elif [[ $current_page -gt 0 ]]; then
                    ((current_page--))
                    cursor_pos=$((items_per_page - 1))
                    local start_idx=$((current_page * items_per_page))
                    local end_idx=$((start_idx + items_per_page - 1))
                    [[ $end_idx -ge $total_items ]] && cursor_pos=$((total_items - start_idx - 1))
                fi
                ;;
            "DOWN")
                local start_idx=$((current_page * items_per_page))
                local items_on_page=$((total_items - start_idx))
                [[ $items_on_page -gt $items_per_page ]] && items_on_page=$items_per_page

                if [[ $cursor_pos -lt $((items_on_page - 1)) ]]; then
                    ((cursor_pos++))
                elif [[ $current_page -lt $((total_pages - 1)) ]]; then
                    ((current_page++))
                    cursor_pos=0
                fi
                ;;
            "LEFT")
                if [[ $current_page -gt 0 ]]; then
                    ((current_page--))
                    cursor_pos=0
                fi
                ;;
            "RIGHT")
                if [[ $current_page -lt $((total_pages - 1)) ]]; then
                    ((current_page++))
                    cursor_pos=0
                fi
                ;;
            "PGUP")
                current_page=0
                cursor_pos=0
                ;;
            "PGDOWN")
                current_page=$((total_pages - 1))
                cursor_pos=0
                ;;
            "SPACE")
                local actual_idx=$((current_page * items_per_page + cursor_pos))
                if [[ $actual_idx -lt $total_items ]]; then
                    if [[ ${selected[actual_idx]} == true ]]; then
                        selected[actual_idx]=false
                    else
                        selected[actual_idx]=true
                    fi
                fi
                ;;
            "ALL")
                for ((i = 0; i < total_items; i++)); do
                    selected[i]=true
                done
                ;;
            "NONE")
                for ((i = 0; i < total_items; i++)); do
                    selected[i]=false
                done
                ;;
            "HELP")
                show_help
                ;;
            "ENTER")
                # If no items are selected, select the current item
                local has_selection=false
                for ((i = 0; i < total_items; i++)); do
                    if [[ ${selected[i]} == true ]]; then
                        has_selection=true
                        break
                    fi
                done

                if [[ $has_selection == false ]]; then
                    # Select current item under cursor
                    local actual_idx=$((current_page * items_per_page + cursor_pos))
                    if [[ $actual_idx -lt $total_items ]]; then
                        selected[actual_idx]=true
                    fi
                fi

                # Build result
                local result=""
                for ((i = 0; i < total_items; i++)); do
                    if [[ ${selected[i]} == true ]]; then
                        result="$result $i"
                    fi
                done
                cleanup
                echo "${result# }"
                return 0
                ;;
            *)
                # Ignore unrecognized keys - just continue the loop
                ;;
        esac
    done
}

# Demo function
demo_paginated() {
    echo "=== Paginated Multi-select Demo ===" >&2

    # Create test data
    local test_items=()
    for i in {1..35}; do
        test_items+=("Application $i ($(( (RANDOM % 500) + 50 ))MB)")
    done

    local result
    result=$(paginated_multi_select "Choose Applications to Uninstall" "${test_items[@]}")
    local exit_code=$?

    if [[ $exit_code -eq 0 ]]; then
        if [[ -n "$result" ]]; then
            echo "Selected indices: $result" >&2
            echo "Count: $(echo $result | wc -w | tr -d ' ')" >&2
        else
            echo "No items selected" >&2
        fi
    else
        echo "Selection cancelled" >&2
    fi
}

# Run demo if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    demo_paginated
fi
