#!/bin/bash

# Better menu system with proper terminal handling
# Uses tried-and-true approach for better compatibility

# Terminal state management
save_terminal() {
    stty -g 2>/dev/null || true
}

restore_terminal() {
    stty "$(save_terminal)" 2>/dev/null || true
    printf '\033[?25h' >&2  # Show cursor
    printf '\033[0m' >&2    # Reset colors
}

# Read a single key (handles arrow keys properly)
read_key() {
    local key
    read -rsn1 key
    case "$key" in
        $'\033')  # ESC sequence
            read -rsn2 key 2>/dev/null || key=""
            case "$key" in
                '[A') echo "UP" ;;
                '[B') echo "DOWN" ;;
                *)    echo "ESC" ;;
            esac
            ;;
        ' ')  echo "SPACE" ;;
        '')   echo "ENTER" ;;
        'q'|'Q') echo "QUIT" ;;
        *)    echo "OTHER" ;;
    esac
}

# Multi-select menu with proper pagination
multi_select_menu() {
    local title="$1"
    shift
    local -a items=("$@")

    if [[ ${#items[@]} -eq 0 ]]; then
        echo "Error: No items provided" >&2
        return 1
    fi

    local -a selected=()
    local current=0
    local page_size=10
    local total=${#items[@]}

    # Initialize selection array
    for ((i = 0; i < total; i++)); do
        selected[i]=false
    done

    # Save terminal state
    local saved_state=""
    saved_state=$(save_terminal)
    trap 'test -n "$saved_state" && stty "$saved_state" 2>/dev/null; restore_terminal' EXIT INT TERM

    while true; do
        # Calculate pagination
        local start_page=$((current / page_size))
        local start_idx=$((start_page * page_size))
        local end_idx=$((start_idx + page_size - 1))
        if [[ $end_idx -ge $total ]]; then
            end_idx=$((total - 1))
        fi

        # Clear screen and show header
        printf '\033[2J\033[H' >&2
        echo "┌─── $title ───┐" >&2
        echo "│ Found $total items (Page $((start_page + 1)) of $(((total + page_size - 1) / page_size))) │" >&2
        echo "└─────────────────────────────────────────────┘" >&2
        echo "" >&2

        # Show items for current page
        for ((i = start_idx; i <= end_idx; i++)); do
            local marker="  "
            local checkbox="☐"

            if [[ $i -eq $current ]]; then
                marker="▶ "
            fi

            if [[ ${selected[i]} == "true" ]]; then
                checkbox="☑"
            fi

            printf "%s%s %s\n" "$marker" "$checkbox" "${items[i]}" >&2
        done

        echo "" >&2
        echo "Controls: ↑/↓=Navigate  Space=Select/Deselect  Enter=Confirm  Q=Quit" >&2

        # Show selection summary
        local count=0
        for ((i = 0; i < total; i++)); do
            if [[ ${selected[i]} == "true" ]]; then
                ((count++))
            fi
        done
        echo "Selected: $count items" >&2
        echo "" >&2

        # Read key
        local key
        key=$(read_key)

        case "$key" in
            "UP")
                ((current--))
                if [[ $current -lt 0 ]]; then
                    current=$((total - 1))
                fi
                ;;
            "DOWN")
                ((current++))
                if [[ $current -ge $total ]]; then
                    current=0
                fi
                ;;
            "SPACE")
                if [[ ${selected[current]} == "true" ]]; then
                    selected[current]=false
                else
                    selected[current]=true
                fi
                ;;
            "ENTER")
                # Build result string
                local result=""
                for ((i = 0; i < total; i++)); do
                    if [[ ${selected[i]} == "true" ]]; then
                        result="$result $i"
                    fi
                done

                # Clean up and return
                restore_terminal
                echo "${result# }"  # Remove leading space
                return 0
                ;;
            "QUIT"|"ESC")
                restore_terminal
                return 1
                ;;
        esac
    done
}

# Simple single-select menu
single_select_menu() {
    local title="$1"
    shift
    local -a items=("$@")

    if [[ ${#items[@]} -eq 0 ]]; then
        echo "Error: No items provided" >&2
        return 1
    fi

    local current=0
    local total=${#items[@]}

    # Save terminal state
    local saved_state=""
    saved_state=$(save_terminal)
    trap 'test -n "$saved_state" && stty "$saved_state" 2>/dev/null; restore_terminal' EXIT INT TERM

    while true; do
        # Clear screen and show header
        printf '\033[2J\033[H' >&2
        echo "┌─── $title ───┐" >&2
        echo "│ Choose one of $total items │" >&2
        echo "└────────────────────────────┘" >&2
        echo "" >&2

        # Show all items
        for ((i = 0; i < total; i++)); do
            local marker="  "
            if [[ $i -eq $current ]]; then
                marker="▶ "
            fi
            printf "%s%s\n" "$marker" "${items[i]}" >&2
        done

        echo "" >&2
        echo "Controls: ↑/↓=Navigate  Enter=Select  Q=Quit" >&2
        echo "" >&2

        # Read key
        local key
        key=$(read_key)

        case "$key" in
            "UP")
                ((current--))
                if [[ $current -lt 0 ]]; then
                    current=$((total - 1))
                fi
                ;;
            "DOWN")
                ((current++))
                if [[ $current -ge $total ]]; then
                    current=0
                fi
                ;;
            "ENTER")
                restore_terminal
                echo "$current"
                return 0
                ;;
            "QUIT"|"ESC")
                restore_terminal
                return 1
                ;;
        esac
    done
}

# Demo function for testing
demo() {
    echo "=== Multi-select Demo ===" >&2
    local result
    result=$(multi_select_menu "Test Multi-Select" "Option 1" "Option 2" "Option 3" "Option 4" "Option 5")
    if [[ $? -eq 0 ]]; then
        echo "You selected indices: $result" >&2
    else
        echo "Selection cancelled" >&2
    fi

    echo "" >&2
    echo "=== Single-select Demo ===" >&2
    result=$(single_select_menu "Test Single-Select" "Choice A" "Choice B" "Choice C")
    if [[ $? -eq 0 ]]; then
        echo "You selected index: $result" >&2
    else
        echo "Selection cancelled" >&2
    fi
}

# Run demo if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    demo
fi