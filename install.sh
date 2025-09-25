#!/bin/bash
# Mole Installation Script
# Install Mole system cleanup tool to your system

set -euo pipefail

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Verbosity (0 = quiet, 1 = verbose)
VERBOSE=1

# Logging functions
log_info() { [[ ${VERBOSE} -eq 1 ]] && echo -e "${BLUE}$1${NC}"; }
log_success() { [[ ${VERBOSE} -eq 1 ]] && echo -e "${GREEN}$1${NC}"; }
log_warning() { [[ ${VERBOSE} -eq 1 ]] && echo -e "${YELLOW}$1${NC}"; }
log_error() { echo -e "${RED}$1${NC}"; }

# Default installation directory
INSTALL_DIR="/usr/local/bin"
CONFIG_DIR="$HOME/.config/mole"
SOURCE_DIR=""

show_help() {
    cat << 'EOF'
Mole Installation Script
========================

USAGE:
    ./install.sh [OPTIONS]

OPTIONS:
    --prefix PATH       Install to custom directory (default: /usr/local/bin)
    --config PATH       Config directory (default: ~/.config/mole)
    --uninstall         Uninstall mole
    --help, -h          Show this help

EXAMPLES:
    ./install.sh                    # Install to /usr/local/bin
    ./install.sh --prefix ~/.local/bin  # Install to custom directory
    ./install.sh --uninstall       # Uninstall mole

The installer will:
1. Copy mole binary and scripts to the install directory
2. Set up config directory with all modules
3. Make the mole command available system-wide
EOF
}

# Resolve the directory containing source files (supports curl | bash)
resolve_source_dir() {
    # 1) If script is on disk, use its directory
    if [[ -n "${BASH_SOURCE[0]:-}" && -f "${BASH_SOURCE[0]}" ]]; then
        local script_dir
        script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
        if [[ -f "$script_dir/mole" || -d "$script_dir/bin" || -d "$script_dir/lib" ]]; then
            SOURCE_DIR="$script_dir"
            return 0
        fi
    fi

    # 2) If CLEAN_SOURCE_DIR env is provided, honor it
    if [[ -n "${CLEAN_SOURCE_DIR:-}" && -d "$CLEAN_SOURCE_DIR" ]]; then
        SOURCE_DIR="$CLEAN_SOURCE_DIR"
        return 0
    fi

    # 3) Fallback: fetch repository to a temp directory (works for curl | bash)
    local tmp
    tmp="$(mktemp -d)"
    # Expand tmp now so trap doesn't depend on local scope
    trap "rm -rf '$tmp'" EXIT

    echo "Fetching Mole source..."
    if command -v curl >/dev/null 2>&1; then
        # Download main branch tarball
        if curl -fsSL -o "$tmp/mole.tar.gz" "https://github.com/tw93/mole/archive/refs/heads/main.tar.gz"; then
            tar -xzf "$tmp/mole.tar.gz" -C "$tmp"
            # Extracted folder name: mole-main
            if [[ -d "$tmp/mole-main" ]]; then
                SOURCE_DIR="$tmp/mole-main"
                return 0
            fi
        fi
    fi

    # 4) Fallback to git if available
    if command -v git >/dev/null 2>&1; then
        if git clone --depth=1 https://github.com/tw93/mole.git "$tmp/mole" >/dev/null 2>&1; then
            SOURCE_DIR="$tmp/mole"
            return 0
        fi
    fi

    log_error "Failed to fetch source files. Ensure curl or git is available."
    exit 1
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --prefix)
                INSTALL_DIR="$2"
                shift 2
                ;;
            --config)
                CONFIG_DIR="$2"
                shift 2
                ;;
            --uninstall)
                uninstall_mole
                exit 0
                ;;
            --verbose|-v)
                VERBOSE=1
                shift 1
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

# Check system requirements
check_requirements() {
    # Check if running on macOS
    if [[ "$OSTYPE" != "darwin"* ]]; then
        log_error "This tool is designed for macOS only"
        exit 1
    fi

    # Check if install directory exists and is writable
    if [[ ! -d "$(dirname "$INSTALL_DIR")" ]]; then
        log_error "Parent directory $(dirname "$INSTALL_DIR") does not exist"
        exit 1
    fi
}

# Create installation directories
create_directories() {
    # Create install directory if it doesn't exist
    if [[ ! -d "$INSTALL_DIR" ]]; then
        if [[ "$INSTALL_DIR" == "/usr/local/bin" ]] && [[ ! -w "$(dirname "$INSTALL_DIR")" ]]; then
            sudo mkdir -p "$INSTALL_DIR"
        else
            mkdir -p "$INSTALL_DIR"
        fi
    fi

    # Create config directory
    mkdir -p "$CONFIG_DIR"
    mkdir -p "$CONFIG_DIR/bin"
    mkdir -p "$CONFIG_DIR/lib"

}

# Install files
install_files() {

    resolve_source_dir

    # Copy main executable
    if [[ -f "$SOURCE_DIR/mole" ]]; then
        if [[ "$INSTALL_DIR" == "/usr/local/bin" ]] && [[ ! -w "$INSTALL_DIR" ]]; then
            sudo cp "$SOURCE_DIR/mole" "$INSTALL_DIR/mole"
            sudo chmod +x "$INSTALL_DIR/mole"
        else
            cp "$SOURCE_DIR/mole" "$INSTALL_DIR/mole"
            chmod +x "$INSTALL_DIR/mole"
        fi
    else
        log_error "mole executable not found in ${SOURCE_DIR:-unknown}"
        exit 1
    fi

    # Copy configuration and modules
    if [[ -d "$SOURCE_DIR/bin" ]]; then
        cp -r "$SOURCE_DIR/bin"/* "$CONFIG_DIR/bin/"
        chmod +x "$CONFIG_DIR/bin"/*
    fi

    if [[ -d "$SOURCE_DIR/lib" ]]; then
        cp -r "$SOURCE_DIR/lib"/* "$CONFIG_DIR/lib/"
    fi

    # Copy other files if they exist
    for file in README.md LICENSE; do
        if [[ -f "$SOURCE_DIR/$file" ]]; then
            cp "$SOURCE_DIR/$file" "$CONFIG_DIR/"
        fi
    done

    # Update the mole script to use the config directory
    if [[ "$INSTALL_DIR" == "/usr/local/bin" ]] && [[ ! -w "$INSTALL_DIR" ]]; then
        sudo sed -i '' "s|SCRIPT_DIR=.*|SCRIPT_DIR=\"$CONFIG_DIR\"|" "$INSTALL_DIR/mole"
    else
        sed -i '' "s|SCRIPT_DIR=.*|SCRIPT_DIR=\"$CONFIG_DIR\"|" "$INSTALL_DIR/mole"
    fi
}

# Verify installation
verify_installation() {

    if [[ -x "$INSTALL_DIR/mole" ]] && [[ -f "$CONFIG_DIR/lib/common.sh" ]]; then

        # Test if mole command works
        if "$INSTALL_DIR/mole" --help >/dev/null 2>&1; then
            log_success ""
        else
            log_warning "Mole command installed but may not be working properly"
        fi
    else
        log_error "Installation verification failed"
        exit 1
    fi
}

# Add to PATH if needed
setup_path() {
    # Check if install directory is in PATH
    if [[ ":$PATH:" == *":$INSTALL_DIR:"* ]]; then
        return
    fi

    # Only suggest PATH setup for custom directories
    if [[ "$INSTALL_DIR" != "/usr/local/bin" ]]; then
        log_warning "$INSTALL_DIR is not in your PATH"
        echo ""
        echo "To use mole from anywhere, add this line to your shell profile:"
        echo "export PATH=\"$INSTALL_DIR:\$PATH\""
        echo ""
        echo "For example, add it to ~/.zshrc or ~/.bash_profile"
    fi
}

# Uninstall function
uninstall_mole() {
    log_info "Uninstalling mole..."

    # Remove executable
    if [[ -f "$INSTALL_DIR/mole" ]]; then
        if [[ "$INSTALL_DIR" == "/usr/local/bin" ]] && [[ ! -w "$INSTALL_DIR" ]]; then
            sudo rm -f "$INSTALL_DIR/mole"
        else
            rm -f "$INSTALL_DIR/mole"
        fi
        log_success "Removed executable from $INSTALL_DIR"
    fi

    # Ask before removing config directory
    if [[ -d "$CONFIG_DIR" ]]; then
        echo ""
        read -p "Remove configuration directory $CONFIG_DIR? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            rm -rf "$CONFIG_DIR"
            log_success "Removed configuration directory"
        else
            log_info "Configuration directory preserved"
        fi
    fi

    log_success "Mole uninstalled successfully"
}

# Main installation function
main() {

    check_requirements
    create_directories
    install_files
    verify_installation
    setup_path

    if [[ ${VERBOSE} -eq 1 ]]; then
        log_success "Mole installed successfully!"
        echo ""
        echo "Usage:"
        if [[ ":$PATH:" == *":$INSTALL_DIR:"* ]]; then
            echo "  mole              # Interactive menu"
            echo "  mole clean        # System cleanup"
            echo "  mole uninstall    # Remove applications"
        else
            echo "  $INSTALL_DIR/mole              # Interactive menu"
            echo "  $INSTALL_DIR/mole clean        # System cleanup"
            echo "  $INSTALL_DIR/mole uninstall    # Remove applications"
        fi
        echo ""
    fi
}

# Run installation
parse_args "$@"
main
