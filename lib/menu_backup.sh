#!/bin/bash

# Simple interactive menu selector with arrow key support
# No external dependencies, compatible with most bash versions

declare -a menu_options=()
declare -i selected=0
declare -i menu_size=0

# ANSI escape sequences
readonly ESC=$'\033'
readonly UP="${ESC}[A"
readonly DOWN="${ESC}[B"
readonly ENTER=$'\n'
readonly CLEAR_LINE="${ESC}[2K"
readonly HIDE_CURSOR="${ESC}[?25l"
readonly SHOW_CURSOR="${ESC}[?25h"

# Set terminal to raw mode for reading single characters
setup_terminal() {
    stty -echo -icanon time 0 min 0
}

# Restore terminal to normal mode
restore_terminal() {
    stty echo icanon
    printf "%s" "$SHOW_CURSOR"
}

# Draw the menu
draw_menu() {
    printf "%s" "$HIDE_CURSOR"

    for ((i = 0; i < menu_size; i++)); do
        printf "\r%s" "$CLEAR_LINE"

        if [[ $i -eq $selected ]]; then
            printf "▶ \033[1;32m%s\033[0m\n" "${menu_options[i]}"
        else
            printf "  %s\n" "${menu_options[i]}"
        fi
    done

    # Move cursor back to the beginning
    printf "${ESC}[%dA" $menu_size
}

# Read a single key
read_key() {
    local key
    IFS= read -r -n1 key 2>/dev/null

    if [[ $key == $ESC ]]; then
        # Handle escape sequences
        IFS= read -r -n2 key 2>/dev/null
        case "$key" in
            '[A') echo "UP" ;;
            '[B') echo "DOWN" ;;
            *) echo "ESC" ;;
        esac
    elif [[ $key == "" ]]; then
        echo "ENTER"
    else
        echo "$key"
    fi
}

# Main menu function
# Usage: show_menu "Title" "option1" "option2" "option3" ...
show_menu() {
    local title="$1"
    shift

    # Initialize menu options
    menu_options=("$@")
    menu_size=${#menu_options[@]}
    selected=0

    # Check if we have options
    if [[ $menu_size -eq 0 ]]; then
        echo "Error: No menu options provided" >&2
        return 1
    fi

    # Setup terminal
    setup_terminal
    trap restore_terminal EXIT INT TERM

    # Display title
    if [[ -n "$title" ]]; then
        printf "\n\033[1;34m%s\033[0m\n\n" "$title"
    fi

    # Initial draw
    draw_menu

    # Main loop
    while true; do
        local key=$(read_key)

        case "$key" in
            "UP")
                ((selected--))
                if [[ $selected -lt 0 ]]; then
                    selected=$((menu_size - 1))
                fi
                draw_menu
                ;;
            "DOWN")
                ((selected++))
                if [[ $selected -ge $menu_size ]]; then
                    selected=0
                fi
                draw_menu
                ;;
            "ENTER")
                # Clear the menu
                for ((i = 0; i < menu_size; i++)); do
                    printf "\r%s\n" "$CLEAR_LINE" >&2
                done
                printf "${ESC}[%dA" $menu_size >&2

                # Show selection
                printf "Selected: \033[1;32m%s\033[0m\n\n" "${menu_options[selected]}"

                restore_terminal
                return $selected
                ;;
            "q"|"Q")
                restore_terminal
                echo "Cancelled." >&2
                return 255
                ;;
            [0-9])
                # Jump to numbered option
                local num=$((key - 1))
                if [[ $num -ge 0 && $num -lt $menu_size ]]; then
                    selected=$num
                    draw_menu
                fi
                ;;
        esac
    done
}

# Multi-select menu function
# Usage: show_multi_menu "Title" "option1" "option2" "option3" ...
show_multi_menu() {
    local title="$1"
    shift

    # Initialize menu options
    menu_options=("$@")
    menu_size=${#menu_options[@]}
    selected=0

    # Array to track selected items
    declare -a selected_items=()
    for ((i = 0; i < menu_size; i++)); do
        selected_items[i]=false
    done

    # Check if we have options
    if [[ $menu_size -eq 0 ]]; then
        echo "Error: No menu options provided" >&2
        return 1
    fi

    # Setup terminal
    setup_terminal
    trap restore_terminal EXIT INT TERM

    # Display title
    if [[ -n "$title" ]]; then
        printf "\n\033[1;34m%s\033[0m\n" "$title" >&2
        printf "\033[0;36mUse SPACE to select/deselect, ENTER to confirm, Q to quit\033[0m\n\n" >&2
    fi

    # Draw multi-select menu
    draw_multi_menu() {
        printf "%s" "$HIDE_CURSOR" >&2

        for ((i = 0; i < menu_size; i++)); do
            printf "\r%s" "$CLEAR_LINE" >&2

            local checkbox="☐"
            if [[ ${selected_items[i]} == "true" ]]; then
                checkbox="\033[1;32m☑\033[0m"
            fi

            if [[ $i -eq $selected ]]; then
                printf "▶ %s \033[1;32m%s\033[0m\n" "$checkbox" "${menu_options[i]}" >&2
            else
                printf "  %s %s\n" "$checkbox" "${menu_options[i]}" >&2
            fi
        done

        # Move cursor back to the beginning
        printf "${ESC}[%dA" $menu_size >&2
    }

    # Initial draw
    draw_multi_menu

    # Main loop
    while true; do
        local key=$(read_key)

        case "$key" in
            "UP")
                ((selected--))
                if [[ $selected -lt 0 ]]; then
                    selected=$((menu_size - 1))
                fi
                draw_multi_menu
                ;;
            "DOWN")
                ((selected++))
                if [[ $selected -ge $menu_size ]]; then
                    selected=0
                fi
                draw_multi_menu
                ;;
            " ")
                # Toggle selection
                if [[ ${selected_items[selected]} == "true" ]]; then
                    selected_items[selected]="false"
                else
                    selected_items[selected]="true"
                fi
                draw_multi_menu
                ;;
            "ENTER")
                # Clear the menu
                for ((i = 0; i < menu_size; i++)); do
                    printf "\r%s\n" "$CLEAR_LINE" >&2
                done
                printf "${ESC}[%dA" $menu_size >&2

                # Show selections to stderr so it doesn't interfere with return value
                local has_selection=false
                printf "Selected items:\n" >&2
                for ((i = 0; i < menu_size; i++)); do
                    if [[ ${selected_items[i]} == "true" ]]; then
                        printf "  \033[1;32m%s\033[0m\n" "${menu_options[i]}" >&2
                        has_selection=true
                    fi
                done

                if [[ $has_selection == "false" ]]; then
                    printf "  None\n" >&2
                fi
                printf "\n" >&2

                restore_terminal

                # Return selected indices as space-separated string
                local result=""
                for ((i = 0; i < menu_size; i++)); do
                    if [[ ${selected_items[i]} == "true" ]]; then
                        result="$result $i"
                    fi
                done
                echo "${result# }"  # Remove leading space
                return 0
                ;;
            "q"|"Q")
                restore_terminal
                echo "Cancelled." >&2
                return 255
                ;;
        esac
    done
}

# Example usage function
demo_menu() {
    echo "=== Single Select Demo ==="
    if show_menu "Choose an action:" "Install package" "Update system" "Clean cache" "Exit"; then
        local choice=$?
        echo "You selected option $choice"
    fi

    echo -e "\n=== Multi Select Demo ==="
    local selections=$(show_multi_menu "Choose packages to install:" "git" "vim" "curl" "htop" "tree")
    if [[ $? -eq 0 && -n "$selections" ]]; then
        echo "Selected indices: $selections"
        # Convert indices to actual values
        local options=("git" "vim" "curl" "htop" "tree")
        echo "Selected packages:"
        for idx in $selections; do
            echo "  - ${options[idx]}"
        done
    fi
}

# If script is run directly, show demo
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    demo_menu
fi