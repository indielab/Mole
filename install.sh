#!/bin/bash

# Clean Your Mac - Installation Script
set -e

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log_info() { echo -e "${BLUE}$1${NC}"; }
log_success() { echo -e "${GREEN}✅ $1${NC}"; }
log_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
log_error() { echo -e "${RED}❌ $1${NC}"; }

echo -e "${BLUE}🧹 Installing Clean Mac...${NC}"

# Check system compatibility
if [[ "$OSTYPE" != "darwin"* ]]; then
    log_error "This tool only supports macOS"
    exit 1
fi

# Check for arguments
FORCE_DIRECT=false
UNINSTALL=false

for arg in "$@"; do
    case $arg in
        --direct)
            FORCE_DIRECT=true
            ;;
        --uninstall)
            UNINSTALL=true
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --direct     Force direct installation (skip Homebrew)"
            echo "  --uninstall  Uninstall clean-mac"
            echo "  --help       Show this help message"
            exit 0
            ;;
    esac
done

# Uninstall function
uninstall_clean() {
    log_info "Uninstalling Clean Mac..."

    # Check if installed via Homebrew
    if command -v brew >/dev/null 2>&1 && brew list clean-mac >/dev/null 2>&1; then
        brew uninstall clean-mac
        log_success "Uninstalled via Homebrew"
    elif [[ -f "/usr/local/bin/clean" ]]; then
        sudo rm -f "/usr/local/bin/clean"
        log_success "Removed from /usr/local/bin"
    else
        log_warning "Clean Mac is not installed"
    fi
    exit 0
}

if [[ "$UNINSTALL" == "true" ]]; then
    uninstall_clean
fi

# Check if already installed
if command -v clean >/dev/null 2>&1 && [[ "$FORCE_DIRECT" != "true" ]]; then
    log_warning "Clean Mac is already installed"
    echo "  Location: $(which clean)"
    echo "  Version: $(clean --help | head -1 || echo 'Unknown')"
    echo ""
    echo "Run with --uninstall to remove, or --direct to reinstall"
    exit 0
fi

# Installation methods
install_via_homebrew() {
    log_info "Installing via Homebrew..."

    if ! command -v brew >/dev/null 2>&1; then
        log_error "Homebrew is not installed"
        echo "Install Homebrew first: https://brew.sh"
        return 1
    fi

    # Add tap if not already added
    if ! brew tap | grep -q "tw93/tap"; then
        log_info "Adding tap: tw93/tap"
        brew tap tw93/tap
    fi

    # Install clean-mac
    brew install clean-mac
    return $?
}

install_direct() {
    log_info "Installing directly to /usr/local/bin..."

    # Create directory
    INSTALL_DIR="/usr/local/bin"
    if [[ ! -d "$INSTALL_DIR" ]]; then
        log_info "Creating install directory..."
        sudo mkdir -p "$INSTALL_DIR"
    fi

    # Download script
    log_info "Downloading latest version..."
    TEMP_FILE=$(mktemp)

    if ! curl -fsSL https://raw.githubusercontent.com/tw93/clean-mac/main/clean.sh -o "$TEMP_FILE"; then
        log_error "Download failed"
        rm -f "$TEMP_FILE"
        return 1
    fi

    # Verify download
    if [[ ! -s "$TEMP_FILE" ]]; then
        log_error "Downloaded file is empty"
        rm -f "$TEMP_FILE"
        return 1
    fi

    # Install
    log_info "Installing..."
    sudo cp "$TEMP_FILE" "$INSTALL_DIR/clean"
    sudo chmod +x "$INSTALL_DIR/clean"
    rm "$TEMP_FILE"

    return 0
}

# Choose installation method - always use direct installation for now
if [[ "$FORCE_DIRECT" == "true" ]]; then
    install_direct
    INSTALL_SUCCESS=$?
else
    # Always use direct installation until homebrew-tap is ready
    log_info "Using direct installation..."
    install_direct
    INSTALL_SUCCESS=$?
fi

# Verify installation
if [[ $INSTALL_SUCCESS -eq 0 ]] && command -v clean >/dev/null 2>&1; then
    log_success "Installation completed successfully!"
    echo ""
    echo -e "${GREEN}Usage:${NC}"
    echo -e "  ${BLUE}clean${NC}          - User-level cleanup (no password required)"
    echo -e "  ${BLUE}clean --system${NC} - Deep system cleanup (password required)"
    echo -e "  ${BLUE}clean --help${NC}   - Show help message"
    echo ""
    echo -e "${GREEN}Try it now:${NC} clean"
else
    log_error "Installation failed"
    echo ""
    echo "You may need to:"
    echo "1. Restart your terminal"
    echo "2. Add /usr/local/bin to your PATH:"
    echo "   export PATH=\"/usr/local/bin:\$PATH\""
    echo "3. Run the installer with --direct flag"
    exit 1
fi