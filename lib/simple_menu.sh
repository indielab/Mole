#!/bin/bash

# Simple, clean menu implementation that properly separates output

# Simple single-select menu - returns selected index
simple_select() {
    local title="$1"
    shift
    local -a options=("$@")
    local selected=0
    local key

    # Clear screen and show header
    clear >&2
    echo "=== $title ===" >&2
    echo "" >&2

    while true; do
        # Show options
        for ((i = 0; i < ${#options[@]}; i++)); do
            if [[ $i -eq $selected ]]; then
                echo "▶ ${options[i]}" >&2
            else
                echo "  ${options[i]}" >&2
            fi
        done
        echo "" >&2
        echo "Use ↑/↓ to navigate, ENTER to select, Q to quit" >&2

        # Read key
        read -rsn1 key
        case "$key" in
            $'\x1b')
                # Arrow key sequence
                read -rsn2 key
                case "$key" in
                    '[A') # Up
                        ((selected--))
                        if [[ $selected -lt 0 ]]; then
                            selected=$((${#options[@]} - 1))
                        fi
                        ;;
                    '[B') # Down
                        ((selected++))
                        if [[ $selected -ge ${#options[@]} ]]; then
                            selected=0
                        fi
                        ;;
                esac
                ;;
            '') # Enter
                echo "$selected"
                return 0
                ;;
            'q'|'Q')
                return 1
                ;;
        esac

        # Clear screen for next iteration
        clear >&2
        echo "=== $title ===" >&2
        echo "" >&2
    done
}

# Multi-select menu - returns space-separated indices
simple_multi_select() {
    local title="$1"
    shift
    local -a options=("$@")
    local selected=0
    local -a selected_items=()
    local key

    # Initialize selected items array
    for ((i = 0; i < ${#options[@]}; i++)); do
        selected_items[i]=false
    done

    clear >&2
    echo "=== $title ===" >&2
    echo "" >&2

    while true; do
        # Show options
        for ((i = 0; i < ${#options[@]}; i++)); do
            local checkbox="☐"
            if [[ ${selected_items[i]} == "true" ]]; then
                checkbox="☑"
            fi

            if [[ $i -eq $selected ]]; then
                echo "▶ $checkbox ${options[i]}" >&2
            else
                echo "  $checkbox ${options[i]}" >&2
            fi
        done
        echo "" >&2
        echo "Use ↑/↓ to navigate, SPACE to select/deselect, ENTER to confirm, Q to quit" >&2

        # Read key
        read -rsn1 key
        case "$key" in
            $'\x1b')
                # Arrow key sequence
                read -rsn2 key
                case "$key" in
                    '[A') # Up
                        ((selected--))
                        if [[ $selected -lt 0 ]]; then
                            selected=$((${#options[@]} - 1))
                        fi
                        ;;
                    '[B') # Down
                        ((selected++))
                        if [[ $selected -ge ${#options[@]} ]]; then
                            selected=0
                        fi
                        ;;
                esac
                ;;
            ' ') # Space - toggle selection
                if [[ ${selected_items[selected]} == "true" ]]; then
                    selected_items[selected]=false
                else
                    selected_items[selected]=true
                fi
                ;;
            '') # Enter - confirm
                local result=""
                for ((i = 0; i < ${#options[@]}; i++)); do
                    if [[ ${selected_items[i]} == "true" ]]; then
                        result="$result $i"
                    fi
                done
                echo "${result# }"  # Remove leading space
                return 0
                ;;
            'q'|'Q')
                return 1
                ;;
        esac

        # Clear screen for next iteration
        clear >&2
        echo "=== $title ===" >&2
        echo "" >&2
    done
}