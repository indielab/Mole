#!/bin/bash
# Mac Tools - Install Module
# Interactive application installer using Homebrew
#
# Usage:
#   install.sh          # Launch interactive installer
#   install.sh --help   # Show help information

set -euo pipefail

# Get script directory and source common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

# Check if Homebrew is available
check_homebrew() {
    if ! command -v brew >/dev/null 2>&1; then
        log_error "Homebrew is not installed"
        echo ""
        echo "To install Homebrew, run:"
        echo '/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'
        exit 1
    fi
}

# Application categories with descriptions
declare -A APP_CATEGORIES=(
    ["productivity"]="📝 Productivity Apps"
    ["development"]="💻 Development Tools"
    ["media"]="🎵 Media & Entertainment"
    ["utilities"]="🔧 System Utilities"
    ["communication"]="💬 Communication"
    ["design"]="🎨 Design & Graphics"
)

# Define applications by category
declare -A APPS=(
    # Productivity
    ["notion"]="productivity|Notion|All-in-one workspace for notes and docs"
    ["obsidian"]="productivity|Obsidian|Knowledge management and note-taking"
    ["raycast"]="productivity|Raycast|Launcher and productivity tool"
    ["alfred"]="productivity|Alfred|Application launcher and productivity app"
    ["1password"]="productivity|1Password|Password manager"

    # Development
    ["visual-studio-code"]="development|VS Code|Code editor by Microsoft"
    ["docker"]="development|Docker|Containerization platform"
    ["postman"]="development|Postman|API development and testing"
    ["github-desktop"]="development|GitHub Desktop|Git client for GitHub"
    ["figma"]="development|Figma|Design and prototyping tool"
    ["iterm2"]="development|iTerm2|Terminal replacement"

    # Media
    ["vlc"]="media|VLC|Media player"
    ["spotify"]="media|Spotify|Music streaming"
    ["handbrake"]="media|HandBrake|Video transcoder"
    ["obs"]="media|OBS Studio|Live streaming and recording"

    # Utilities
    ["the-unarchiver"]="utilities|The Unarchiver|Archive utility"
    ["appcleaner"]="utilities|AppCleaner|Uninstall applications completely"
    ["cleanmymac"]="utilities|CleanMyMac X|System cleaning and optimization"
    ["bartender-4"]="utilities|Bartender 4|Menu bar organization"

    # Communication
    ["discord"]="communication|Discord|Voice and text chat"
    ["slack"]="communication|Slack|Team communication"
    ["telegram"]="communication|Telegram|Messaging app"
    ["zoom"]="communication|Zoom|Video conferencing"

    # Design
    ["sketch"]="design|Sketch|Digital design toolkit"
    ["adobe-creative-cloud"]="design|Adobe CC|Creative suite"
    ["blender"]="design|Blender|3D creation suite"
)

# Initialize global variables
declare -a selected_apps=()
declare -a filtered_apps=()
current_category="all"
current_line=0

# Help information
show_help() {
    echo "Mole - Interactive App Installer"
    echo "================================="
    echo ""
    echo "Description: Install useful applications using Homebrew Cask"
    echo ""
    echo "Features:"
    echo "  • Browse apps by category"
    echo "  • Navigate with ↑/↓ arrow keys"
    echo "  • Select/deselect apps with SPACE"
    echo "  • Filter by category with 1-6 keys"
    echo "  • Install selected apps with ENTER"
    echo "  • Quit anytime with 'q'"
    echo ""
    echo "Usage:"
    echo "  ./install.sh          Launch interactive installer"
    echo "  ./install.sh --help   Show this help message"
    echo ""
    echo "Requirements:"
    echo "  • Homebrew must be installed"
    echo "  • Internet connection for downloads"
    echo ""
}

# Parse arguments
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    show_help
    exit 0
fi

# Filter apps by category
filter_apps_by_category() {
    local category="$1"
    filtered_apps=()

    for app_key in "${!APPS[@]}"; do
        IFS='|' read -r app_category app_name app_desc <<< "${APPS[$app_key]}"
        if [[ "$category" == "all" || "$app_category" == "$category" ]]; then
            filtered_apps+=("$app_key|$app_category|$app_name|$app_desc")
        fi
    done

    # Sort alphabetically by name
    IFS=$'\n' filtered_apps=($(sort -t'|' -k3 <<<"${filtered_apps[*]}"))
    unset IFS
}

# Display application list
display_apps() {
    clear
    echo "📦 Mole - Interactive App Installer"
    echo "══════════════════════════════════════════════════════════════════════"
    echo ""

    # Show category filter
    local category_name="All Applications"
    case "$current_category" in
        "productivity") category_name="${APP_CATEGORIES[productivity]}" ;;
        "development") category_name="${APP_CATEGORIES[development]}" ;;
        "media") category_name="${APP_CATEGORIES[media]}" ;;
        "utilities") category_name="${APP_CATEGORIES[utilities]}" ;;
        "communication") category_name="${APP_CATEGORIES[communication]}" ;;
        "design") category_name="${APP_CATEGORIES[design]}" ;;
    esac

    echo -e "${PURPLE}Category: $category_name${NC}"
    echo -e "${PURPLE}Showing ${#filtered_apps[@]} applications${NC}"
    echo ""

    # Display apps (max 15 per page)
    local start_idx=0
    local end_idx=$((${#filtered_apps[@]} - 1))
    local max_display=15

    if [[ $end_idx -gt $((max_display - 1)) ]]; then
        end_idx=$((max_display - 1))
    fi

    for ((i=start_idx; i<=end_idx && i<${#filtered_apps[@]}; i++)); do
        IFS='|' read -r app_key app_category app_name app_desc <<< "${filtered_apps[i]}"

        local prefix="  "
        local line_color="$NC"
        local name_color="$NC"

        # Current selection highlighting
        if [[ $i -eq $current_line ]]; then
            prefix="▶ "
            line_color="$BLUE"
            name_color="$BLUE"
        fi

        # Check if app is selected
        local checkbox="[ ]"
        local checkbox_color="$NC"
        for selected in "${selected_apps[@]}"; do
            if [[ "$selected" == "$app_key" ]]; then
                checkbox="[✓]"
                checkbox_color="$GREEN"
                break
            fi
        done

        # Format display
        printf "${line_color}${prefix}${checkbox_color}${checkbox}${NC} "
        printf "${name_color}%-25s${NC} " "$app_name"
        printf "│ %s\n" "$app_desc"
    done

    echo ""
    echo "──────────────────────────────────────────────────────────────────────"

    # Show selection summary
    local selected_count=${#selected_apps[@]}
    if [[ $selected_count -eq 0 ]]; then
        echo -e "${BLUE}📋 No applications selected${NC}"
    else
        echo -e "${GREEN}📋 Selected: $selected_count applications${NC}"
    fi

    echo ""

    # Show category filters
    echo -e "${PURPLE}🏷️  Categories:${NC}"
    echo "  0 All  1 Productivity  2 Development  3 Media  4 Utilities  5 Communication  6 Design"
    echo ""

    # Controls
    echo -e "${PURPLE}🎮 Controls:${NC}"
    echo "  ↑/↓ Navigate  SPACE Select  0-6 Filter  ENTER Install  ? Help  q Quit"
}

# Interactive app selection
interactive_app_selection() {
    filter_apps_by_category "$current_category"
    current_line=0

    while true; do
        display_apps

        # Read key input
        read -rsn1 key

        case "$key" in
            $'\x1b')  # ESC sequences
                read -rsn2 key
                case "$key" in
                    '[A')  # Up arrow
                        ((current_line > 0)) && ((current_line--))
                        ;;
                    '[B')  # Down arrow
                        ((current_line < ${#filtered_apps[@]} - 1)) && ((current_line++))
                        ;;
                esac
                ;;
            ' ')  # Space - toggle selection
                if [[ ${#filtered_apps[@]} -gt 0 && $current_line -lt ${#filtered_apps[@]} ]]; then
                    IFS='|' read -r app_key app_category app_name app_desc <<< "${filtered_apps[current_line]}"

                    # Check if already selected
                    local found=false
                    for i in "${!selected_apps[@]}"; do
                        if [[ "${selected_apps[i]}" == "$app_key" ]]; then
                            unset 'selected_apps[i]'
                            selected_apps=("${selected_apps[@]}")  # Re-index array
                            found=true
                            break
                        fi
                    done

                    if [[ "$found" == "false" ]]; then
                        selected_apps+=("$app_key")
                    fi
                fi
                ;;
            $'\n'|$'\r')  # Enter - proceed to installation
                if [[ ${#selected_apps[@]} -gt 0 ]]; then
                    break
                fi
                ;;
            'q'|'Q')  # Quit
                log_info "Installation cancelled"
                return 1
                ;;
            [0-6])  # Category filters
                case "$key" in
                    '0') current_category="all" ;;
                    '1') current_category="productivity" ;;
                    '2') current_category="development" ;;
                    '3') current_category="media" ;;
                    '4') current_category="utilities" ;;
                    '5') current_category="communication" ;;
                    '6') current_category="design" ;;
                esac
                filter_apps_by_category "$current_category"
                current_line=0
                ;;
            'a'|'A')  # Select all visible
                for app_data in "${filtered_apps[@]}"; do
                    IFS='|' read -r app_key app_category app_name app_desc <<< "$app_data"

                    # Check if already selected
                    local found=false
                    for selected in "${selected_apps[@]}"; do
                        if [[ "$selected" == "$app_key" ]]; then
                            found=true
                            break
                        fi
                    done

                    if [[ "$found" == "false" ]]; then
                        selected_apps+=("$app_key")
                    fi
                done
                ;;
            'n'|'N')  # Select none
                selected_apps=()
                ;;
            '?')  # Help
                show_help
                echo ""
                read -p "Press any key to continue..." -n 1 -r
                ;;
        esac
    done

    return 0
}

# Install selected applications
install_applications() {
    log_header "Installing selected applications"

    echo "You selected ${#selected_apps[@]} application(s) for installation:"
    echo ""

    for app_key in "${selected_apps[@]}"; do
        IFS='|' read -r app_category app_name app_desc <<< "${APPS[$app_key]}"
        echo "  • $app_name - $app_desc"
    done

    echo ""
    read -p "Continue with installation? (y/N): " -n 1 -r
    echo

    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo ""
        log_info "Starting installation..."
        echo ""

        local successful=0
        local failed=0

        for app_key in "${selected_apps[@]}"; do
            IFS='|' read -r app_category app_name app_desc <<< "${APPS[$app_key]}"

            echo -e "${BLUE}Installing $app_name...${NC}"

            if brew install --cask "$app_key" 2>/dev/null; then
                echo -e "  ${GREEN}✓${NC} $app_name installed successfully"
                ((successful++))
            else
                echo -e "  ${RED}✗${NC} Failed to install $app_name"
                ((failed++))
            fi
            echo ""
        done

        # Summary
        echo "══════════════════════════════════════════════════════════════════════"
        log_success "Installation complete!"
        echo "📊 Successfully installed: $successful applications"
        if [[ $failed -gt 0 ]]; then
            echo "⚠️  Failed to install: $failed applications"
        fi
    else
        log_info "Installation cancelled"
    fi
}

# Main function
main() {
    echo "📦 Mole - Interactive App Installer"
    echo "===================================="
    echo ""

    # Check Homebrew
    check_homebrew

    log_info "Checking Homebrew installation..."
    echo ""

    # Interactive selection
    if ! interactive_app_selection; then
        return 0
    fi

    clear
    install_applications

    log_success "App installer finished"
}

# Run main function
main "$@"