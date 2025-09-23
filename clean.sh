#!/bin/bash
# Clean Mac - Deep Clean Your Mac with One Click
#
# 🧹 One-click cleanup tool for macOS cache and leftovers
# 🍎 Optimized for Apple Silicon with comprehensive dev tool support
#
# Quick install:
# curl -fsSL https://raw.githubusercontent.com/tw93/clean-mac/main/install.sh | bash
#
# Usage:
#   clean           # Daily cleanup (safe, no password)
#   clean --system  # Deep system cleanup (requires password)
#   clean --help    # Show help information
#
# GitHub: https://github.com/tw93/clean-mac
# License: MIT © tw93

# ANSI color palette
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
PURPLE='\033[0;35m'
RED='\033[0;31m'
NC='\033[0m'

log_info() { echo -e "${BLUE}$1${NC}"; }
log_success() { echo -e "${GREEN}✅ $1${NC}"; }
log_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
log_error() { echo -e "${RED}❌ $1${NC}"; }
log_header() { echo -e "\n${PURPLE}▶ $1${NC}"; }

PRESERVED_BUNDLE_PATTERNS=(
    "com.apple.*"
    "com.nektony.*"
)

if [[ -n "$CLEAN_PRESERVE_BUNDLES" ]]; then
    IFS=',' read -r -a extra_patterns <<< "$CLEAN_PRESERVE_BUNDLES"
    PRESERVED_BUNDLE_PATTERNS+=("${extra_patterns[@]}")
fi

should_preserve_bundle() {
    local bundle_id="$1"
    for pattern in "${PRESERVED_BUNDLE_PATTERNS[@]}"; do
        if [[ "$bundle_id" == $pattern ]]; then
            return 0
        fi
    done
    return 1
}

LAST_CLEAN_RESULT=0
SECTION_ACTIVITY=0
TRACK_SECTION=0
SUDO_KEEPALIVE_PID=""

note_activity() {
    if [[ $TRACK_SECTION -eq 1 ]]; then
        SECTION_ACTIVITY=1
    fi
}

cleanup() {
    if [[ -n "$SUDO_KEEPALIVE_PID" ]]; then
        kill "$SUDO_KEEPALIVE_PID" 2>/dev/null || true
        SUDO_KEEPALIVE_PID=""
    fi
}

trap cleanup EXIT INT TERM

start_section() {
    TRACK_SECTION=1
    SECTION_ACTIVITY=0
    log_header "$1"
}

end_section() {
    if [[ $TRACK_SECTION -eq 1 && $SECTION_ACTIVITY -eq 0 ]]; then
        echo -e "  ${BLUE}✨${NC} Nothing to tidy"
    fi
    TRACK_SECTION=0
}

# Configuration
SYSTEM_CLEAN=false

# Argument parsing
while [[ $# -gt 0 ]]; do
    case $1 in
        --help|-h)
            echo "Usage: clean [OPTIONS]"
            echo ""
            echo "Description: Clean Mac - Deep Clean Your Mac with One Click"
            echo ""
            echo "Options:"
            echo "  --system    Include system-level cleanup (requires password)"
            echo "  --help      Show this help message"
            echo ""
            echo "Default: Cleans user-level cache and data (no password required)"
            exit 0
            ;;
        --system)
            SYSTEM_CLEAN=true
            shift
            ;;
        *)
            log_error "Unknown option: $1"
            echo "Use --help to view available options"
            exit 1
            ;;
    esac
done

# Detect Mac architecture
ARCH=$(uname -m)
IS_M_SERIES=false
if [[ "$ARCH" == "arm64" ]]; then
    IS_M_SERIES=true
fi

# Privilege escalation helper
request_sudo() {
    if [[ "$SKIP_SYSTEM" == "true" ]]; then
        return 0
    fi
    log_info "Administrator privileges are required for system-level cleanup..."
    if ! sudo -v; then
        log_warning "System-level cleanup skipped (sudo unavailable)"
        SKIP_SYSTEM=true
        return 1
    fi
    # Keep sudo session alive
    while true; do sudo -n true; sleep 60; kill -0 "$$" 2>/dev/null || exit; done 2>/dev/null &
    SUDO_KEEPALIVE_PID=$!
}

# Safe cleanup helper
safe_clean() {
    if [[ $# -eq 0 ]]; then
        return 0
    fi

    local description
    local -a targets

    if [[ $# -eq 1 ]]; then
        description="$1"
        targets=("$1")
    else
        description="${@: -1}"
        targets=("${@:1:$#-1}")
    fi

    local removed_any=0

    for path in "${targets[@]}"; do
        if [[ ! -e "$path" ]]; then
            continue
        fi

        local size_bytes=$(du -sk "$path" 2>/dev/null | awk '{print $1}' || echo "0")
        local size_human=$(du -sh "$path" 2>/dev/null | awk '{print $1}' || echo "0B")
        local count=$(find "$path" -type f 2>/dev/null | wc -l | tr -d ' ')

        if [[ "$count" -eq 0 || "$size_bytes" -eq 0 ]]; then
            continue
        fi

        rm -rf "$path" 2>/dev/null || true

        local label="$description"
        if [[ ${#targets[@]} -gt 1 ]]; then
            label+=" [$(basename "$path")"]
        fi

        echo -e "  ${GREEN}✓${NC} $label ${GREEN}($size_human)${NC}"
        ((files_cleaned+=count))
        ((total_size_cleaned+=size_bytes))
        ((total_items++))
        removed_any=1
        note_activity
    done

    LAST_CLEAN_RESULT=$removed_any
    return $removed_any
}

# Prompt before cleaning non-cache application data
confirm_clean() {
    local path="$1"
    local description="${2:-$path}"
    local app_name="$3"

    if [[ ! -e "$path" ]]; then
        return 0
    fi

    local size_human=$(du -sh "$path" 2>/dev/null | cut -f1 || echo "0B")
    local count=$(find "$path" -type f 2>/dev/null | wc -l | tr -d ' ')

    if [[ "$count" -gt 0 ]]; then
        echo -e "  ${YELLOW}⚠️${NC}  Found $app_name data: ${GREEN}($size_human)${NC}"
        read -p "    Clean $app_name data? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            safe_clean "$path" "$description"
        else
            echo -e "  ${BLUE}ℹ${NC}  Skipped $app_name data"
        fi
    fi
}

# Detect orphaned application leftovers
check_orphaned_apps() {
    log_header "Checking for orphaned app files"

    # Build a list of installed application bundle identifiers
    local installed_bundles=$(mktemp)
    find /Applications -name "*.app" -exec sh -c 'defaults read "$1/Contents/Info.plist" CFBundleIdentifier 2>/dev/null' _ {} \; > "$installed_bundles" 2>/dev/null

    local found_orphaned=false

    # Inspect the Caches directory
    find ~/Library/Caches -maxdepth 1 -name "com.*" -type d | while read cache_dir; do
        local bundle_id=$(basename "$cache_dir")
        if should_preserve_bundle "$bundle_id"; then
            continue
        fi
        if ! grep -q "$bundle_id" "$installed_bundles"; then
            safe_clean "$cache_dir" "Orphaned cache: $bundle_id"
            found_orphaned=true
        fi
    done

    # Inspect the Application Support directory
    find ~/Library/Application\ Support -maxdepth 1 -name "com.*" -type d | while read support_dir; do
        local bundle_id=$(basename "$support_dir")
        if should_preserve_bundle "$bundle_id"; then
            continue
        fi
        if ! grep -q "$bundle_id" "$installed_bundles"; then
            safe_clean "$support_dir" "Orphaned data: $bundle_id"
            found_orphaned=true
        fi
    done

    # Inspect the Preferences directory
    find ~/Library/Preferences -maxdepth 1 -name "com.*.plist" -type f | while read pref_file; do
        local bundle_id=$(basename "$pref_file" .plist)
        if should_preserve_bundle "$bundle_id"; then
            continue
        fi
        if ! grep -q "$bundle_id" "$installed_bundles"; then
            safe_clean "$pref_file" "Orphaned preference: $bundle_id"
            found_orphaned=true
        fi
    done

    if [[ "$found_orphaned" == "false" ]]; then
        echo -e "  ${GREEN}✓${NC} No orphaned files found"
    fi

    rm -f "$installed_bundles"
}

# Apple Silicon specific cache cleanup
clean_command_cache() {
    if [[ "$IS_M_SERIES" == "true" ]]; then
        local silicon_cleaned=0

        # Rosetta 2 cache
        safe_clean /Library/Apple/usr/share/rosetta/rosetta_update_bundle "Rosetta 2 cache"
        ((silicon_cleaned |= LAST_CLEAN_RESULT))
        safe_clean ~/Library/Caches/com.apple.rosetta.update "Rosetta 2 user cache"
        ((silicon_cleaned |= LAST_CLEAN_RESULT))

        # Additional Apple Silicon caches
        safe_clean ~/Library/Caches/com.apple.amp.mediasevicesd "Apple Silicon media service cache"
        ((silicon_cleaned |= LAST_CLEAN_RESULT))
        safe_clean ~/Library/Caches/com.apple.bird.lsuseractivity "User activity cache"
        ((silicon_cleaned |= LAST_CLEAN_RESULT))

        if [[ $silicon_cleaned -eq 0 ]]; then
            echo -e "  ${BLUE}✨${NC} Apple Silicon caches are already tidy"
        fi
    fi
}

echo "🧹 Clean Mac - Deep Clean Your Mac with One Click"
echo "================================================"
space_before=$(df / | tail -1 | awk '{print $4}')
current_space=$(df -h / | tail -1 | awk '{print $4}')

if [[ "$IS_M_SERIES" == "true" ]]; then
    echo "🍎 Detected: Apple Silicon (M-series) | 💾 Free space: $current_space"
else
    echo "💻 Detected: Intel Mac | 💾 Free space: $current_space"
fi

if [[ "$SYSTEM_CLEAN" == "true" ]]; then
    echo "🚀 Mode: Full cleanup (user + system)"
else
    echo "🚀 Mode: User-level cleanup (no password required)"
fi

# Initialize counters
total_items=0
files_cleaned=0
total_size_cleaned=0

# ===== 1. System essentials =====
start_section "System essentials"
safe_clean ~/Library/Caches/* "User app cache"
safe_clean ~/Library/Logs/* "User app logs"
safe_clean ~/.Trash/* "Trash"

# Empty the trash on all mounted volumes
for volume in /Volumes/*; do
    [[ -d "$volume/.Trashes" ]] && safe_clean "$volume/.Trashes"/* "External volume trash"
done

safe_clean ~/Library/Application\ Support/CrashReporter/* "Crash reports"
safe_clean ~/Library/DiagnosticReports/* "Diagnostic reports"
safe_clean ~/Library/Caches/com.apple.QuickLook.thumbnailcache "QuickLook thumbnails"
safe_clean ~/Library/Caches/Quick\ Look/* "QuickLook cache"
safe_clean ~/Library/Caches/com.apple.LaunchServices* "Launch services cache"
safe_clean ~/Library/Caches/com.apple.iconservices* "Icon services cache"
safe_clean ~/Library/Caches/CloudKit/* "CloudKit cache"
safe_clean ~/Library/Caches/com.apple.bird* "iCloud cache"

end_section

# ===== 2. Browsers =====
start_section "Browser cleanup"
# Safari
safe_clean ~/Library/Caches/com.apple.Safari/* "Safari cache"
safe_clean ~/Library/Safari/LocalStorage/* "Safari local storage"
safe_clean ~/Library/Safari/Databases/* "Safari databases"

# Chrome/Chromium family
safe_clean ~/Library/Caches/Google/Chrome/* "Chrome cache"
safe_clean ~/Library/Application\ Support/Google/Chrome/*/Application\ Cache/* "Chrome app cache"
safe_clean ~/Library/Application\ Support/Google/Chrome/*/GPUCache/* "Chrome GPU cache"
safe_clean ~/Library/Caches/Chromium/* "Chromium cache"

# Other browsers
safe_clean ~/Library/Caches/com.microsoft.edgemac/* "Edge cache"
safe_clean ~/Library/Caches/company.thebrowser.Browser/* "Arc cache"
safe_clean ~/Library/Caches/BraveSoftware/Brave-Browser/* "Brave cache"
safe_clean ~/Library/Caches/Firefox/* "Firefox cache"
safe_clean ~/Library/Caches/com.operasoftware.Opera/* "Opera cache"
safe_clean ~/Library/Caches/com.vivaldi.Vivaldi/* "Vivaldi cache"

end_section

# ===== 3. Developer tools =====
start_section "Developer tools"

# Node.js ecosystem
if command -v npm >/dev/null 2>&1; then
    npm cache clean --force >/dev/null 2>&1 || true
    echo -e "  ${GREEN}✓${NC} npm cache cleaned"
    note_activity
fi

safe_clean ~/.npm/_cacache/* "npm cache directory"
safe_clean ~/.yarn/cache/* "Yarn cache"
safe_clean ~/.bun/install/cache/* "Bun cache"

# Python ecosystem
if command -v pip3 >/dev/null 2>&1; then
    pip3 cache purge >/dev/null 2>&1 || true
    echo -e "  ${GREEN}✓${NC} pip cache cleaned"
    note_activity
fi
safe_clean ~/Library/Caches/pip/* "pip cache directory"
safe_clean ~/.pyenv/cache/* "pyenv cache"

# Go tooling
if command -v go >/dev/null 2>&1; then
    go clean -modcache >/dev/null 2>&1 || true
    go clean -cache >/dev/null 2>&1 || true
    echo -e "  ${GREEN}✓${NC} Go cache cleaned"
    note_activity
fi

# Homebrew cleanup
safe_clean ~/Library/Caches/Homebrew/* "Homebrew cache"
safe_clean /opt/homebrew/var/homebrew/locks/* "Homebrew lock files (M series)"
safe_clean /usr/local/var/homebrew/locks/* "Homebrew lock files (Intel)"

# Docker
if command -v docker >/dev/null 2>&1; then
    docker system prune -af --volumes >/dev/null 2>&1 || true
    echo -e "  ${GREEN}✓${NC} Docker resources cleaned"
    note_activity
fi

# Container tools
safe_clean ~/.kube/cache/* "Kubernetes cache"
if command -v podman >/dev/null 2>&1; then
    podman system prune -af --volumes >/dev/null 2>&1 || true
    echo -e "  ${GREEN}✓${NC} Podman resources cleaned"
    note_activity
fi
safe_clean ~/.local/share/containers/storage/tmp/* "Container storage temp"

# Cloud CLI tools
safe_clean ~/.aws/cli/cache/* "AWS CLI cache"
safe_clean ~/.config/gcloud/logs/* "Google Cloud logs"
safe_clean ~/.azure/logs/* "Azure CLI logs"

end_section

# ===== 4. Applications =====
start_section "Applications"

# Xcode & iOS development
safe_clean ~/Library/Developer/Xcode/DerivedData/* "Xcode derived data"
safe_clean ~/Library/Developer/Xcode/Archives/* "Xcode archives"
safe_clean ~/Library/Developer/CoreSimulator/Caches/* "Simulator cache"
safe_clean ~/Library/Developer/CoreSimulator/Devices/*/data/tmp/* "Simulator temp files"
safe_clean ~/Library/Caches/com.apple.dt.Xcode/* "Xcode cache"

# VS Code family
safe_clean ~/Library/Application\ Support/Code/logs/* "VS Code logs"
safe_clean ~/Library/Application\ Support/Code/CachedExtensions/* "VS Code extension cache"
safe_clean ~/Library/Application\ Support/Code/CachedData/* "VS Code data cache"

# JetBrains IDEs
safe_clean ~/Library/Logs/IntelliJIdea*/* "IntelliJ IDEA logs"
safe_clean ~/Library/Logs/PhpStorm*/* "PhpStorm logs"
safe_clean ~/Library/Logs/PyCharm*/* "PyCharm logs"
safe_clean ~/Library/Logs/WebStorm*/* "WebStorm logs"
safe_clean ~/Library/Logs/GoLand*/* "GoLand logs"
safe_clean ~/Library/Logs/CLion*/* "CLion logs"
safe_clean ~/Library/Logs/DataGrip*/* "DataGrip logs"
safe_clean ~/Library/Caches/JetBrains/* "JetBrains cache"

# Communication and social apps
safe_clean ~/Library/Application\ Support/discord/Cache/* "Discord cache"
safe_clean ~/Library/Application\ Support/Slack/Cache/* "Slack cache"
safe_clean ~/Library/Caches/us.zoom.xos/* "Zoom cache"
safe_clean ~/Library/Caches/com.tencent.xinWeChat/* "WeChat cache"
safe_clean ~/Library/Caches/ru.keepcoder.Telegram/* "Telegram cache"
safe_clean ~/Library/Caches/com.openai.chat/* "ChatGPT cache"
safe_clean ~/Library/Caches/com.anthropic.claudefordesktop/* "Claude desktop cache"
safe_clean ~/Library/Logs/Claude/* "Claude logs"
safe_clean ~/Library/Caches/com.microsoft.teams2/* "Microsoft Teams cache"
safe_clean ~/Library/Caches/net.whatsapp.WhatsApp/* "WhatsApp cache"
safe_clean ~/Library/Caches/com.skype.skype/* "Skype cache"

# Design and creative software
safe_clean ~/Library/Caches/com.bohemiancoding.sketch3/* "Sketch cache"
safe_clean ~/Library/Application\ Support/com.bohemiancoding.sketch3/cache/* "Sketch app cache"
safe_clean ~/Library/Caches/net.telestream.screenflow10/* "ScreenFlow cache"

# Productivity and dev utilities
safe_clean ~/Library/Caches/com.raycast.macos/* "Raycast cache"
safe_clean ~/Library/Caches/com.tw93.MiaoYan/* "MiaoYan cache"
safe_clean ~/Library/Caches/com.filo.client/* "Filo cache"
safe_clean ~/Library/Caches/com.flomoapp.mac/* "Flomo cache"

# Music and entertainment
safe_clean ~/Library/Caches/com.spotify.client/* "Spotify cache"

# Gaming and entertainment
safe_clean ~/Library/Caches/com.valvesoftware.steam/* "Steam cache"
safe_clean ~/Library/Caches/com.epicgames.EpicGamesLauncher/* "Epic Games cache"

# Utilities and productivity
safe_clean ~/Library/Caches/com.nektony.App-Cleaner-SIIICn/* "App Cleaner cache"
safe_clean ~/Library/Caches/com.runjuu.Input-Source-Pro/* "Input Source Pro cache"
safe_clean ~/Library/Caches/macos-wakatime.WakaTime/* "WakaTime cache"
safe_clean ~/Library/Caches/notion.id/* "Notion cache"
safe_clean ~/Library/Caches/md.obsidian/* "Obsidian cache"
safe_clean ~/Library/Caches/com.1password.*/* "1Password cache"
safe_clean ~/Library/Caches/com.runningwithcrayons.Alfred/* "Alfred cache"
safe_clean ~/Library/Caches/cx.c3.theunarchiver/* "The Unarchiver cache"
safe_clean ~/Library/Caches/com.freemacsoft.AppCleaner/* "AppCleaner cache"

end_section

# ===== 5. Orphaned leftovers =====
check_orphaned_apps

# Common temp and test data
safe_clean ~/Library/Application\ Support/TestApp* "Test app data"
safe_clean ~/Library/Application\ Support/MyApp/* "Test app data"
safe_clean ~/Library/Application\ Support/GitHub*/* "GitHub test data"
safe_clean ~/Library/Application\ Support/Twitter*/* "Twitter test data"
safe_clean ~/Library/Application\ Support/TestNoValue/* "Test data"
safe_clean ~/Library/Application\ Support/Wk*/* "Test data"

# ===== 6. Apple Silicon specific =====
if [[ "$IS_M_SERIES" == "true" ]]; then
    log_header "Apple Silicon cache cleanup"
    clean_command_cache
fi

# ===== 6. Extended dev caches =====
start_section "Extended developer caches"

# Additional Node.js and frontend tools
safe_clean ~/.pnpm-store/* "pnpm store cache"
safe_clean ~/.cache/typescript/* "TypeScript cache"
safe_clean ~/.cache/electron/* "Electron cache"
safe_clean ~/.cache/yarn/* "Yarn cache"
safe_clean ~/.turbo/* "Turbo cache"
safe_clean ~/.next/* "Next.js cache"
safe_clean ~/.vite/* "Vite cache"
safe_clean ~/.cache/vite/* "Vite global cache"
safe_clean ~/.cache/webpack/* "Webpack cache"
safe_clean ~/.parcel-cache/* "Parcel cache"

# Design and development tools
safe_clean ~/Library/Caches/Google/AndroidStudio*/* "Android Studio cache"
safe_clean ~/Library/Caches/com.unity3d.*/* "Unity cache"
safe_clean ~/Library/Caches/com.postmanlabs.mac/* "Postman cache"
safe_clean ~/Library/Caches/com.konghq.insomnia/* "Insomnia cache"
safe_clean ~/Library/Caches/com.tinyapp.TablePlus/* "TablePlus cache"
safe_clean ~/Library/Caches/com.mongodb.compass/* "MongoDB Compass cache"
safe_clean ~/Library/Caches/com.figma.Desktop/* "Figma cache"
safe_clean ~/Library/Caches/com.github.GitHubDesktop/* "GitHub Desktop cache"
safe_clean ~/Library/Caches/com.microsoft.VSCode/* "VS Code cache"
safe_clean ~/Library/Caches/com.sublimetext.*/* "Sublime Text cache"

# Python tooling
safe_clean ~/.cache/poetry/* "Poetry cache"
safe_clean ~/.cache/uv/* "uv cache"
safe_clean ~/.cache/ruff/* "Ruff cache"
safe_clean ~/.cache/mypy/* "MyPy cache"
safe_clean ~/.pytest_cache/* "Pytest cache"

# AI/ML and Data Science tools
safe_clean ~/.jupyter/runtime/* "Jupyter runtime cache"
safe_clean ~/.cache/huggingface/* "Hugging Face cache"
safe_clean ~/.cache/torch/* "PyTorch cache"
safe_clean ~/.cache/tensorflow/* "TensorFlow cache"
safe_clean ~/.conda/pkgs/* "Conda packages cache"
safe_clean ~/anaconda3/pkgs/* "Anaconda packages cache"
safe_clean ~/.cache/wandb/* "Weights & Biases cache"

# Rust tooling
safe_clean ~/.cargo/registry/cache/* "Cargo registry cache"
safe_clean ~/.cargo/git/* "Cargo git cache"

# Java tooling
safe_clean ~/.gradle/caches/* "Gradle caches"
safe_clean ~/.m2/repository/* "Maven repository cache"
safe_clean ~/.sbt/* "SBT cache"

# Git and version control
safe_clean ~/.cache/pre-commit/* "pre-commit cache"
safe_clean ~/.gitconfig.bak* "Git config backup"

# Mobile development
safe_clean ~/.cache/flutter/* "Flutter cache"
safe_clean ~/.gradle/daemon/* "Gradle daemon logs"
safe_clean ~/Library/Developer/Xcode/iOS\ DeviceSupport/*/Symbols/System/Library/Caches/* "iOS device cache"
safe_clean ~/.android/cache/* "Android SDK cache"

# Other language tool caches
safe_clean ~/.cache/swift-package-manager/* "Swift package manager cache"
safe_clean ~/.cache/bazel/* "Bazel cache"
safe_clean ~/.cache/zig/* "Zig cache"
safe_clean ~/.cache/deno/* "Deno cache"

# Database tools
safe_clean ~/Library/Caches/com.sequel-ace.sequel-ace/* "Sequel Ace cache"
safe_clean ~/Library/Caches/com.eggerapps.Sequel-Pro/* "Sequel Pro cache"
safe_clean ~/Library/Caches/redis-desktop-manager/* "Redis Desktop Manager cache"

# Terminal and shell tools
safe_clean ~/.oh-my-zsh/cache/* "Oh My Zsh cache"
safe_clean ~/.config/fish/fish_history.bak* "Fish shell backup"
safe_clean ~/.bash_history.bak* "Bash history backup"
safe_clean ~/.zsh_history.bak* "Zsh history backup"

# Code quality and analysis
safe_clean ~/.sonar/* "SonarQube cache"
safe_clean ~/.cache/eslint/* "ESLint cache"
safe_clean ~/.cache/prettier/* "Prettier cache"

# Additional system-level caches
safe_clean ~/Library/Caches/SentryCrash/* "Sentry crash reports"
safe_clean ~/Library/Caches/KSCrash/* "KSCrash reports"
safe_clean ~/Library/Caches/com.crashlytics.data/* "Crashlytics data"
safe_clean ~/Library/Saved\ Application\ State/* "App state files"
safe_clean ~/Library/HTTPStorages/* "HTTP storage cache"

# Network and download caches
safe_clean ~/Library/Caches/curl/* "curl cache"
safe_clean ~/Library/Caches/wget/* "wget cache"
safe_clean ~/Library/Caches/CocoaPods/* "CocoaPods cache"

# Package managers and dependencies
safe_clean ~/.bundle/cache/* "Ruby Bundler cache"
safe_clean ~/.composer/cache/* "PHP Composer cache"
safe_clean ~/.nuget/packages/* "NuGet packages cache"
safe_clean ~/.ivy2/cache/* "Ivy cache"
safe_clean ~/.pub-cache/* "Dart Pub cache"

# API and monitoring tools
safe_clean ~/Library/Caches/com.getpaw.Paw/* "Paw API cache"
safe_clean ~/Library/Caches/com.charlesproxy.charles/* "Charles Proxy cache"
safe_clean ~/Library/Caches/com.proxyman.NSProxy/* "Proxyman cache"
safe_clean ~/.grafana/cache/* "Grafana cache"
safe_clean ~/.prometheus/data/wal/* "Prometheus WAL cache"

# CI/CD tools
safe_clean ~/.jenkins/workspace/*/target/* "Jenkins workspace cache"
safe_clean ~/.cache/gitlab-runner/* "GitLab Runner cache"
safe_clean ~/.github/cache/* "GitHub Actions cache"
safe_clean ~/.circleci/cache/* "CircleCI cache"


end_section

# System-level cleanup function
run_system_cleanup() {
    log_header "System-level deep clean"

    # Request elevated privileges
    request_sudo

    if [[ "$SKIP_SYSTEM" != "true" ]]; then
        sudo rm -rf /Library/Caches/* 2>/dev/null || true
        sudo rm -rf /private/var/log/asl/* 2>/dev/null || true
        sudo rm -rf /private/var/tmp/* 2>/dev/null || true
        sudo rm -rf /tmp/* 2>/dev/null || true
        sudo rm -rf /private/var/vm/sleepimage 2>/dev/null || true

        # Refresh system caches
        sudo dscacheutil -flushcache 2>/dev/null || true
        sudo killall -HUP mDNSResponder 2>/dev/null || true
        sudo atsutil databases -remove 2>/dev/null || true

        # Font caches and system services
        sudo atsutil databases -removeUser 2>/dev/null || true
        sudo atsutil databases -remove 2>/dev/null || true

        # Additional system logs
        sudo rm -rf /var/log/install.log* 2>/dev/null || true
        sudo rm -rf /var/log/system.log.* 2>/dev/null || true
        sudo rm -rf /Library/Logs/DiagnosticReports/* 2>/dev/null || true

        # CloudKit and iCloud cache (risky)
        sudo rm -rf ~/Library/Application\ Support/CloudDocs/session/containers/* 2>/dev/null || true
        sudo rm -rf ~/Library/Group\ Containers/* 2>/dev/null || true
        sudo rm -rf ~/Library/WebKit/*/IDBSessionStorage/* 2>/dev/null || true
        sudo rm -rf ~/Library/Caches/CloudKit/CloudKitMetadata 2>/dev/null || true

        # Alibaba suite
        sudo rm -rf ~/Library/Caches/com.alibaba.AliLang.osx/* 2>/dev/null || true
        sudo rm -rf ~/Library/Caches/com.alibaba.alilang3.osx/* 2>/dev/null || true
        sudo rm -rf ~/Library/Logs/AliLangClient/* 2>/dev/null || true

        # Adobe Creative Suite (risky data)
        sudo rm -rf ~/Library/Caches/com.adobe.* 2>/dev/null || true
        sudo rm -rf ~/Library/Caches/com.apple.FinalCut* 2>/dev/null || true
        sudo rm -rf ~/Library/Caches/com.blackmagic-design.DaVinciResolve/* 2>/dev/null || true
        sudo rm -rf ~/Library/Caches/com.macpaw.CleanMyMac* 2>/dev/null || true

        # Virtual machines (potentially large but risky)
        sudo rm -rf ~/Library/Caches/com.parallels.* 2>/dev/null || true
        sudo rm -rf ~/Library/Caches/com.vmware.fusion/* 2>/dev/null || true

        # Memory cleanup
        sudo purge 2>/dev/null || true

        echo -e "  ${GREEN}✓${NC} System-level cache and services cleaned"
    else
        echo -e "  ${BLUE}ℹ${NC} System-level cleanup skipped"
    fi
}

# ===== 7. System-level deep clean =====
if [[ "$SYSTEM_CLEAN" == "true" ]]; then
    run_system_cleanup
fi

# iOS device backups
log_header "Checking iOS device backups..."

backup_dir="$HOME/Library/Application Support/MobileSync/Backup"

if [[ -d "$backup_dir" ]] && find "$backup_dir" -mindepth 1 -maxdepth 1 | read -r _; then
  backup_kb=$(du -sk "$backup_dir" 2>/dev/null | awk '{print $1}')
  if [[ -n "${backup_kb:-}" && "$backup_kb" -gt 102400 ]]; then # >100MB
    backup_human=$(du -shm "$backup_dir" 2>/dev/null | awk '{print $1"M"}')
    echo -e "  👉 Found ${GREEN}${backup_human}${NC}, you can delete it manually"
    echo -e "  👉 ${backup_dir}"
  else
    echo -e "  ✨ Nothing to tidy"
  fi
else
  echo -e "  ✨ Nothing to tidy"
fi

# ===== 7. Summary =====
log_header "Cleanup summary"
space_after=$(df / | tail -1 | awk '{print $4}')
current_space_after=$(df -h / | tail -1 | awk '{print $4}')

echo "==================================================================="
space_freed_kb=$((space_after - space_before))
if [[ $space_freed_kb -gt 0 ]]; then
    freed_gb=$(echo "$space_freed_kb" | awk '{printf "%.2f", $1/1024/1024}')
    echo -e "🎉 User-level cleanup complete | 💾 Freed space: ${RED}${freed_gb}GB${NC}"
else
    echo "🎉 User-level cleanup complete"
fi
echo "📊 Items processed: $total_items | 💾 Free space now: $current_space_after"

if [[ "$IS_M_SERIES" == "true" ]]; then
    echo "✨ Apple Silicon optimizations finished"
fi

# Prompt for system-level cleanup if not already done
if [[ "$SYSTEM_CLEAN" != "true" ]]; then
    echo ""
    echo -e "${BLUE}💡 Want even more space?${NC}"
    echo -e "   Run: ${GREEN}clean --system${NC} for deep system cleanup (requires password)"
    echo -e "   This cleans system cache, temp files, and performs memory optimization"
fi

echo "==================================================================="
