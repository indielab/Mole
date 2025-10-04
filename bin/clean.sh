#!/bin/bash
# Mole - Deeper system cleanup
# Complete cleanup with smart password handling

set -euo pipefail

# Get script directory and source common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

# Configuration
SYSTEM_CLEAN=false
DRY_RUN=false
IS_M_SERIES=$([ "$(uname -m)" = "arm64" ] && echo "true" || echo "false")
# Default whitelist patterns to avoid removing critical caches (can be extended by user)
WHITELIST_PATTERNS=("$HOME/Library/Caches/ms-playwright*")
# Load user-defined whitelist file if present (~/.config/mole/whitelist)
if [[ -f "$HOME/.config/mole/whitelist" ]]; then
    while IFS= read -r line; do
        # Trim leading/trailing whitespace without relying on external tools
        line="${line#${line%%[![:space:]]*}}"
        line="${line%${line##*[![:space:]]}}"
        [[ -z "$line" || "$line" =~ ^# ]] && continue
        # Expand leading ~ for user convenience
        [[ "$line" == ~* ]] && line="${line/#~/$HOME}"
        WHITELIST_PATTERNS+=("$line")
    done < "$HOME/.config/mole/whitelist"
fi
total_items=0

# Tracking variables
TRACK_SECTION=0
SECTION_ACTIVITY=0
LAST_CLEAN_RESULT=0
files_cleaned=0
total_size_cleaned=0
SUDO_KEEPALIVE_PID=""

note_activity() {
    if [[ $TRACK_SECTION -eq 1 ]]; then
        SECTION_ACTIVITY=1
    fi
}

# Cleanup background processes
cleanup() {
    if [[ -n "$SUDO_KEEPALIVE_PID" ]]; then
        kill "$SUDO_KEEPALIVE_PID" 2>/dev/null || true
        SUDO_KEEPALIVE_PID=""
    fi
    if [[ -n "$SPINNER_PID" ]]; then
        kill "$SPINNER_PID" 2>/dev/null || true
        SPINNER_PID=""
    fi
}

trap cleanup EXIT INT TERM

# Loading animation functions
SPINNER_PID=""
start_spinner() {
    local message="$1"

    # Check if we're in an interactive terminal
    if [[ ! -t 1 ]]; then
        # Non-interactive, just show static message
        echo -n "  ${BLUE}🔍${NC} $message"
        return
    fi

    # Display message without newline
    echo -n "  ${BLUE}🔍${NC} $message"

    # Start simple dots animation for interactive terminals
    (
        local delay=0.5
        while true; do
            printf "\r  ${BLUE}🔍${NC} $message.  "
            sleep $delay
            printf "\r  ${BLUE}🔍${NC} $message.. "
            sleep $delay
            printf "\r  ${BLUE}🔍${NC} $message..."
            sleep $delay
            printf "\r  ${BLUE}🔍${NC} $message   "
            sleep $delay
        done
    ) &
    SPINNER_PID=$!
}

stop_spinner() {
    local result_message="${1:-Done}"

    if [[ ! -t 1 ]]; then
        # Non-interactive, just show result
        echo " ✓ $result_message"
        return
    fi

    if [[ -n "$SPINNER_PID" ]]; then
        kill "$SPINNER_PID" 2>/dev/null
        wait "$SPINNER_PID" 2>/dev/null
        SPINNER_PID=""
        # Clear the line and show result
        printf "\r  ${GREEN}✓${NC} %s\n" "$result_message"
    else
        # No spinner was running, just show result
        echo "  ${GREEN}✓${NC} $result_message"
    fi
}

# Cleanup background processes on exit

start_section() {
    TRACK_SECTION=1
    SECTION_ACTIVITY=0
    echo ""
    echo -e "${PURPLE}▶ $1${NC}"
}

end_section() {
    if [[ $TRACK_SECTION -eq 1 && $SECTION_ACTIVITY -eq 0 ]]; then
        echo -e "  ${BLUE}✨${NC} Nothing to tidy"
    fi
    TRACK_SECTION=0
}

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
    local total_size_bytes=0
    local total_count=0

    # Optimized: skip size calculation for empty checks, just try to delete
    # Size calculation is the slowest part - do it in parallel
    local -a existing_paths=()
    for path in "${targets[@]}"; do
        # Skip if path matches whitelist
        local skip=false
        for w in "${WHITELIST_PATTERNS[@]}"; do
            if [[ "$path" == $w ]]; then
                skip=true; break
            fi
        done
        [[ "$skip" == "true" ]] && continue
        [[ -e "$path" ]] && existing_paths+=("$path")
    done

    if [[ ${#existing_paths[@]} -eq 0 ]]; then
        LAST_CLEAN_RESULT=0
        return 0
    fi

    # Fast parallel processing for multiple targets
    if [[ ${#existing_paths[@]} -gt 3 ]]; then
        local temp_dir=$(mktemp -d)

        # Launch parallel du jobs (bash 3.2 compatible)
        local -a pids=()
        for path in "${existing_paths[@]}"; do
            (
                local size=$(du -sk "$path" 2>/dev/null | awk '{print $1}' || echo "0")
                local count=$(find "$path" -type f 2>/dev/null | wc -l | tr -d ' ')
                echo "$size $count" > "$temp_dir/$(echo -n "$path" | shasum -a 256 | cut -d' ' -f1)"
            ) &
            pids+=($!)

            # Limit to 15 parallel jobs (bash 3.2 compatible)
            if (( ${#pids[@]} >= 15 )); then
                wait "${pids[0]}" 2>/dev/null || true
                pids=("${pids[@]:1}")
            fi
        done

        # Wait for remaining jobs
        for pid in "${pids[@]}"; do
            wait "$pid" 2>/dev/null || true
        done

        # Collect results and delete
        for path in "${existing_paths[@]}"; do
            local hash=$(echo -n "$path" | shasum -a 256 | cut -d' ' -f1)
            if [[ -f "$temp_dir/$hash" ]]; then
                read -r size count < "$temp_dir/$hash"
                if [[ "$count" -gt 0 && "$size" -gt 0 ]]; then
                    if [[ "$DRY_RUN" != "true" ]]; then
                        rm -rf "$path" 2>/dev/null || true
                    fi
                    ((total_size_bytes += size))
                    ((total_count += count))
                    removed_any=1
                fi
            fi
        done

        rm -rf "$temp_dir"
    else
        # Serial processing for few targets (faster than parallel overhead)
        for path in "${existing_paths[@]}"; do
            local size_bytes=$(du -sk "$path" 2>/dev/null | awk '{print $1}' || echo "0")
            local count=$(find "$path" -type f 2>/dev/null | wc -l | tr -d ' ')

            if [[ "$count" -gt 0 && "$size_bytes" -gt 0 ]]; then
                if [[ "$DRY_RUN" != "true" ]]; then
                    rm -rf "$path" 2>/dev/null || true
                fi
                ((total_size_bytes += size_bytes))
                ((total_count += count))
                removed_any=1
            fi
        done
    fi

    # Only show output if something was actually cleaned
    if [[ $removed_any -eq 1 ]]; then
        local size_human
        if [[ $total_size_bytes -gt 1048576 ]]; then  # > 1GB
            size_human=$(echo "$total_size_bytes" | awk '{printf "%.1fGB", $1/1024/1024}')
        elif [[ $total_size_bytes -gt 1024 ]]; then  # > 1MB
            size_human=$(echo "$total_size_bytes" | awk '{printf "%.1fMB", $1/1024}')
        else
            size_human="${total_size_bytes}KB"
        fi

        local label="$description"
        if [[ ${#targets[@]} -gt 1 ]]; then
            label+=" (${#targets[@]} items)"
        fi

        if [[ "$DRY_RUN" == "true" ]]; then
            echo -e "  ${YELLOW}→${NC} $label ${YELLOW}($size_human, dry)${NC}"
        else
            echo -e "  ${GREEN}✓${NC} $label ${GREEN}($size_human)${NC}"
        fi
        ((files_cleaned+=total_count))
        ((total_size_cleaned+=total_size_bytes))
        ((total_items++))
        note_activity
    fi

    LAST_CLEAN_RESULT=$removed_any
    return 0
}

start_cleanup() {
    clear
    echo ""
    echo -e "${PURPLE}🧹 Clean Your Mac${NC}"
    echo ""
    echo "Mole will remove app caches, browser data, developer tools, and temporary files."

    if [[ "$DRY_RUN" != "true" && -t 0 ]]; then
        echo ""
        echo -e "${BLUE}Tip:${NC} Want a preview first? Run 'mole clean --dry-run'."
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        echo ""
        echo -e "${YELLOW}🧪 Dry Run mode:${NC} showing what would be removed (no deletions)."
        echo ""
        SYSTEM_CLEAN=false
        return
    fi

    if [[ -t 0 ]]; then
        echo ""
        echo "System-level cleanup removes system caches and temp files, optional."
        echo -en "${BLUE}Enter admin password to enable, or press Enter to skip: ${NC}"
        read -s password
        echo ""
        
        if [[ -n "$password" ]] && echo "$password" | sudo -S true 2>/dev/null; then
            SYSTEM_CLEAN=true
            # Start sudo keepalive with error handling
            (
                local retry_count=0
                while true; do
                    if ! sudo -n true 2>/dev/null; then
                        ((retry_count++))
                        if [[ $retry_count -ge 3 ]]; then
                            exit 1
                        fi
                        sleep 5
                        continue
                    fi
                    retry_count=0
                    sleep 30
                    kill -0 "$$" 2>/dev/null || exit
                done
            ) 2>/dev/null &
            SUDO_KEEPALIVE_PID=$!
        else
            SYSTEM_CLEAN=false
            if [[ -n "$password" ]]; then
                echo ""
                echo -e "${YELLOW}⚠️  Invalid password, continuing with user-level cleanup${NC}"
            fi
        fi
    else
        SYSTEM_CLEAN=false
        echo ""
        echo -e "${BLUE}ℹ${NC}  Running in non-interactive mode"
        echo "   • System-level cleanup skipped (requires interaction)"
        echo "   • User-level cleanup will proceed automatically"
        echo ""
    fi
}

perform_cleanup() {
    echo ""
    echo "🍎 $(detect_architecture) | 💾 Free space: $(get_free_space)"

    # Get initial space
    space_before=$(df / | tail -1 | awk '{print $4}')

    # Initialize counters
    total_items=0
    files_cleaned=0
    total_size_cleaned=0

    # ===== 1. System cleanup (if admin) - Do this first while sudo is fresh =====
    if [[ "$SYSTEM_CLEAN" == "true" ]]; then
        start_section "System-level cleanup"

        # Clean system caches more safely - avoid input method and system service caches
        sudo find /Library/Caches -name "*.cache" -delete 2>/dev/null || true
        sudo find /Library/Caches -name "*.tmp" -delete 2>/dev/null || true
        sudo find /Library/Caches -type f -name "*.log" -delete 2>/dev/null || true
        sudo rm -rf /tmp/* 2>/dev/null && log_success "System temp files" || true
        sudo rm -rf /var/tmp/* 2>/dev/null && log_success "System var temp" || true
        log_success "System library caches (safely cleaned)"

        end_section
    fi


    # ===== 2. User essentials =====
    start_section "System essentials"
    safe_clean ~/Library/Caches/* "User app cache"
    safe_clean ~/Library/Logs/* "User app logs"
    safe_clean ~/.Trash/* "Trash"

    # Empty the trash on all mounted volumes
    if [[ -d "/Volumes" ]]; then
        for volume in /Volumes/*; do
            if [[ -d "$volume" && -d "$volume/.Trashes" ]]; then
                find "$volume/.Trashes" -mindepth 1 -maxdepth 1 -exec rm -rf {} \; 2>/dev/null || true
            fi
        done
    fi

    safe_clean ~/Library/Application\ Support/CrashReporter/* "Crash reports"
    safe_clean ~/Library/DiagnosticReports/* "Diagnostic reports"
    safe_clean ~/Library/Caches/com.apple.QuickLook.thumbnailcache "QuickLook thumbnails"
    safe_clean ~/Library/Caches/Quick\ Look/* "QuickLook cache"
    safe_clean ~/Library/Caches/com.apple.LaunchServices* "Launch services cache"
    safe_clean ~/Library/Caches/com.apple.iconservices* "Icon services cache"
    safe_clean ~/Library/Caches/CloudKit/* "CloudKit cache"
    safe_clean ~/Library/Caches/com.apple.bird* "iCloud cache"
    end_section


    # ===== 3. macOS System Caches =====
    start_section "macOS system caches"
    # Saved Application State only stores window positions/sizes, not login data
    safe_clean ~/Library/Saved\ Application\ State/* "Saved application states"
    safe_clean ~/Library/Caches/com.apple.spotlight "Spotlight cache"
    safe_clean ~/Library/Caches/com.apple.metadata "Metadata cache"
    safe_clean ~/Library/Caches/com.apple.FontRegistry "Font registry cache"
    safe_clean ~/Library/Caches/com.apple.ATS "Font cache"
    safe_clean ~/Library/Caches/com.apple.photoanalysisd "Photo analysis cache"
    # Apple ID cache is safe to clean, login credentials are stored elsewhere
    safe_clean ~/Library/Caches/com.apple.akd "Apple ID cache"
    end_section


    # ===== 4. Sandboxed App Caches =====
    start_section "Sandboxed app caches"
    # Clean specific high-usage apps first for better user feedback
    safe_clean ~/Library/Containers/com.apple.wallpaper.agent/Data/Library/Caches/* "Wallpaper agent cache"
    safe_clean ~/Library/Containers/com.apple.mediaanalysisd/Data/Library/Caches/* "Media analysis cache"
    safe_clean ~/Library/Containers/com.apple.AppStore/Data/Library/Caches/* "App Store cache"
    # General pattern last (may match many apps)
    safe_clean ~/Library/Containers/*/Data/Library/Caches/* "Sandboxed app caches"
    end_section


    # ===== 5. Browsers =====
    start_section "Browser cleanup"
    # Safari (cache only, NOT local storage or databases to preserve login states)
    safe_clean ~/Library/Caches/com.apple.Safari/* "Safari cache"

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

    # Browser support files
    safe_clean ~/Library/Application\ Support/Firefox/Profiles/*/cache2/* "Firefox profile cache"
    end_section


    # ===== 6. Cloud Storage =====
    start_section "Cloud storage caches"
    # Only cache files, not sync state or login credentials
    safe_clean ~/Library/Caches/com.dropbox.* "Dropbox cache"
    safe_clean ~/Library/Caches/com.getdropbox.dropbox "Dropbox cache"
    safe_clean ~/Library/Caches/com.google.GoogleDrive "Google Drive cache"
    safe_clean ~/Library/Caches/com.baidu.netdisk "Baidu Netdisk cache"
    safe_clean ~/Library/Caches/com.alibaba.teambitiondisk "Alibaba Cloud cache"
    safe_clean ~/Library/Caches/com.box.desktop "Box cache"
    safe_clean ~/Library/Caches/com.microsoft.OneDrive "OneDrive cache"
    end_section


    # ===== 7. Office Applications =====
    start_section "Office applications"
    safe_clean ~/Library/Caches/com.microsoft.Word "Microsoft Word cache"
    safe_clean ~/Library/Caches/com.microsoft.Excel "Microsoft Excel cache"
    safe_clean ~/Library/Caches/com.microsoft.Powerpoint "Microsoft PowerPoint cache"
    safe_clean ~/Library/Caches/com.apple.iWork.* "Apple iWork cache"
    safe_clean ~/Library/Caches/com.kingsoft.wpsoffice.mac "WPS Office cache"
    end_section


    # ===== 8. Developer tools =====
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

    safe_clean ~/.cache/pip/* "pip cache directory"
    safe_clean ~/Library/Caches/pip/* "pip cache (macOS)"
    safe_clean ~/.pyenv/cache/* "pyenv cache"

    # Go ecosystem
    if command -v go >/dev/null 2>&1; then
        go clean -modcache >/dev/null 2>&1 || true
        go clean -cache >/dev/null 2>&1 || true
        echo -e "  ${GREEN}✓${NC} Go cache cleaned"
        note_activity
    fi

    safe_clean ~/Library/Caches/go-build/* "Go build cache"
    safe_clean ~/go/pkg/mod/cache/* "Go module cache"

    # Rust
    safe_clean ~/.cargo/registry/cache/* "Rust cargo cache"

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

    # Homebrew cleanup
    safe_clean ~/Library/Caches/Homebrew/* "Homebrew cache"
    safe_clean /opt/homebrew/var/homebrew/locks/* "Homebrew lock files (M series)"
    safe_clean /usr/local/var/homebrew/locks/* "Homebrew lock files (Intel)"
    if command -v brew >/dev/null 2>&1; then
        brew cleanup >/dev/null 2>&1 || true
        echo -e "  ${GREEN}✓${NC} Homebrew cache cleaned"
        note_activity
    fi

    # Git
    safe_clean ~/.gitconfig.lock "Git config lock"
    end_section

    # ===== 9. Extended developer caches =====
    start_section "Extended developer caches"

    # Additional Node.js and frontend tools
    safe_clean ~/.pnpm-store/* "pnpm store cache"
    safe_clean ~/.cache/typescript/* "TypeScript cache"
    safe_clean ~/.cache/electron/* "Electron cache"
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
    safe_clean ~/.cargo/git/* "Cargo git cache"

    # Java tooling
    safe_clean ~/.gradle/caches/* "Gradle caches"
    safe_clean ~/.m2/repository/* "Maven repository cache"
    safe_clean ~/.sbt/* "SBT cache"

    # Cloud and container tools
    safe_clean ~/.docker/buildx/cache/* "Docker BuildX cache"
    safe_clean ~/.cache/terraform/* "Terraform cache"

    # API and network development tools
    safe_clean ~/Library/Caches/com.getpaw.Paw/* "Paw API cache"
    safe_clean ~/Library/Caches/com.charlesproxy.charles/* "Charles Proxy cache"
    safe_clean ~/Library/Caches/com.proxyman.NSProxy/* "Proxyman cache"

    # CI/CD tools
    safe_clean ~/.grafana/cache/* "Grafana cache"
    safe_clean ~/.prometheus/data/wal/* "Prometheus WAL cache"
    safe_clean ~/.jenkins/workspace/*/target/* "Jenkins workspace cache"
    safe_clean ~/.cache/gitlab-runner/* "GitLab Runner cache"
    safe_clean ~/.github/cache/* "GitHub Actions cache"
    safe_clean ~/.circleci/cache/* "CircleCI cache"

    # Additional development tools
    safe_clean ~/.oh-my-zsh/cache/* "Oh My Zsh cache"
    safe_clean ~/.config/fish/fish_history.bak* "Fish shell backup"
    safe_clean ~/.bash_history.bak* "Bash history backup"
    safe_clean ~/.zsh_history.bak* "Zsh history backup"
    safe_clean ~/.sonar/* "SonarQube cache"
    safe_clean ~/.cache/eslint/* "ESLint cache"
    safe_clean ~/.cache/prettier/* "Prettier cache"

    # Mobile development
    safe_clean ~/Library/Caches/CocoaPods/* "CocoaPods cache"
    safe_clean ~/.bundle/cache/* "Ruby Bundler cache"
    safe_clean ~/.composer/cache/* "PHP Composer cache"
    safe_clean ~/.nuget/packages/* "NuGet packages cache"
    safe_clean ~/.ivy2/cache/* "Ivy cache"
    safe_clean ~/.pub-cache/* "Dart Pub cache"

    # Network tools cache
    safe_clean ~/.cache/curl/* "curl cache"
    safe_clean ~/.cache/wget/* "wget cache"
    safe_clean ~/Library/Caches/curl/* "curl cache (macOS)"
    safe_clean ~/Library/Caches/wget/* "wget cache (macOS)"

    # Git and version control
    safe_clean ~/.cache/pre-commit/* "pre-commit cache"
    safe_clean ~/.gitconfig.bak* "Git config backup"

    # Mobile development additional
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
    safe_clean ~/Library/Caches/com.navicat.* "Navicat cache"
    safe_clean ~/Library/Caches/com.dbeaver.* "DBeaver cache"
    safe_clean ~/Library/Caches/com.redis.RedisInsight "Redis Insight cache"

    # Crash reports and debugging
    safe_clean ~/Library/Caches/SentryCrash/* "Sentry crash reports"
    safe_clean ~/Library/Caches/KSCrash/* "KSCrash reports"
    safe_clean ~/Library/Caches/com.crashlytics.data/* "Crashlytics data"
    safe_clean ~/Library/HTTPStorages/* "HTTP storage cache"

    end_section


    # ===== 10. Applications =====
    start_section "Applications"

    # Xcode & iOS development
    safe_clean ~/Library/Developer/Xcode/DerivedData/* "Xcode derived data"
    safe_clean ~/Library/Developer/Xcode/Archives/* "Xcode archives"
    safe_clean ~/Library/Developer/CoreSimulator/Caches/* "Simulator cache"
    safe_clean ~/Library/Developer/CoreSimulator/Devices/*/data/tmp/* "Simulator temp files"
    safe_clean ~/Library/Caches/com.apple.dt.Xcode/* "Xcode cache"
    safe_clean ~/Library/Developer/Xcode/iOS\ Device\ Logs/* "iOS device logs"
    safe_clean ~/Library/Developer/Xcode/watchOS\ Device\ Logs/* "watchOS device logs"
    safe_clean ~/Library/Developer/Xcode/Products/* "Xcode build products"

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
    safe_clean ~/Library/Caches/com.apple.Music "Apple Music cache"
    safe_clean ~/Library/Caches/com.apple.podcasts "Apple Podcasts cache"
    safe_clean ~/Library/Caches/tv.plex.player.desktop "Plex cache"
    safe_clean ~/Library/Caches/com.netease.163music "NetEase Music cache"
    safe_clean ~/Library/Caches/com.colliderli.iina "IINA cache"
    safe_clean ~/Library/Caches/org.videolan.vlc "VLC cache"
    safe_clean ~/Library/Caches/io.mpv "MPV cache"
    safe_clean ~/Library/Caches/com.iqiyi.player "iQIYI cache"
    safe_clean ~/Library/Caches/com.tencent.tenvideo "Tencent Video cache"

    # Download tools
    safe_clean ~/Library/Caches/net.xmac.aria2gui "Aria2 cache"
    safe_clean ~/Library/Caches/org.m0k.transmission "Transmission cache"
    safe_clean ~/Library/Caches/com.qbittorrent.qBittorrent "qBittorrent cache"
    safe_clean ~/Library/Caches/com.downie.Downie-* "Downie cache"

    # Gaming and entertainment
    safe_clean ~/Library/Caches/com.valvesoftware.steam/* "Steam cache"
    safe_clean ~/Library/Caches/com.epicgames.EpicGamesLauncher/* "Epic Games cache"

    # Translation tools
    safe_clean ~/Library/Caches/com.youdao.YoudaoDict "Youdao Dictionary cache"
    safe_clean ~/Library/Caches/com.eudic.* "Eudict cache"
    safe_clean ~/Library/Caches/com.bob-build.Bob "Bob Translation cache"

    # Screenshot and recording tools
    safe_clean ~/Library/Caches/com.cleanshot.* "CleanShot cache"
    safe_clean ~/Library/Caches/com.reincubate.camo "Camo cache"
    safe_clean ~/Library/Caches/com.xnipapp.xnip "Xnip cache"

    # Email clients (only cache, NOT database files)
    safe_clean ~/Library/Caches/com.readdle.smartemail-Mac "Spark cache"
    safe_clean ~/Library/Caches/com.airmail.* "Airmail cache"

    # Task management
    safe_clean ~/Library/Caches/com.todoist.mac.Todoist "Todoist cache"
    safe_clean ~/Library/Caches/com.any.do.* "Any.do cache"

    # Shell and command line
    safe_clean ~/.zcompdump* "Zsh completion cache"
    safe_clean ~/.lesshst "less history"
    safe_clean ~/.viminfo.tmp "Vim temporary files"
    safe_clean ~/.wget-hsts "wget HSTS cache"

    # Utilities and productivity (only cache, avoid license/settings data)
    safe_clean ~/Library/Caches/com.runjuu.Input-Source-Pro/* "Input Source Pro cache"
    safe_clean ~/Library/Caches/macos-wakatime.WakaTime/* "WakaTime cache"
    safe_clean ~/Library/Caches/notion.id/* "Notion cache"
    safe_clean ~/Library/Caches/md.obsidian/* "Obsidian cache"
    safe_clean ~/Library/Caches/com.runningwithcrayons.Alfred/* "Alfred cache"
    safe_clean ~/Library/Caches/cx.c3.theunarchiver/* "The Unarchiver cache"

    # Note: Skipping App Cleaner, 1Password and similar apps to preserve licenses

    end_section


    # ===== 11. Virtualization Tools =====
    start_section "Virtualization tools"
    safe_clean ~/Library/Caches/com.vmware.fusion "VMware Fusion cache"
    safe_clean ~/Library/Caches/com.parallels.* "Parallels cache"
    safe_clean ~/VirtualBox\ VMs/.cache "VirtualBox cache"
    safe_clean ~/.vagrant.d/tmp/* "Vagrant temporary files"
    end_section


    # ===== 12. Orphaned leftovers =====
    start_section "Orphaned app files"

    # Build a list of installed application bundle identifiers
    echo -n "  ${BLUE}🔍${NC} Scanning installed applications..."
    local installed_bundles=$(mktemp)
    # More robust approach that won't hang
    for app in /Applications/*.app; do
        if [[ -d "$app" && -f "$app/Contents/Info.plist" ]]; then
            bundle_id=$(defaults read "$app/Contents/Info.plist" CFBundleIdentifier 2>/dev/null || echo "")
            [[ -n "$bundle_id" ]] && echo "$bundle_id" >> "$installed_bundles"
        fi
    done
    local app_count=$(wc -l < "$installed_bundles" | tr -d ' ')
    echo " ${GREEN}✓${NC} Found $app_count apps"

    local found_orphaned=false
    local cache_count=0
    local data_count=0
    local pref_count=0

    # Check for orphaned caches (with protection for critical system settings)
    echo -n "  ${BLUE}🔍${NC} Scanning cache directories..."
    if ls ~/Library/Caches/com.* >/dev/null 2>&1; then
        for cache_dir in ~/Library/Caches/com.*; do
            [[ -d "$cache_dir" ]] || continue
            local bundle_id=$(basename "$cache_dir")
            # CRITICAL: Skip system-essential and protected app caches
            if should_protect_data "$bundle_id"; then
                continue
            fi
            if ! grep -q "$bundle_id" "$installed_bundles" 2>/dev/null; then
                safe_clean "$cache_dir" "Orphaned cache: $bundle_id"
                found_orphaned=true
                ((cache_count++))
            fi
        done
    fi
    echo " ${GREEN}✓${NC} Complete ($cache_count removed)"

    # Check for orphaned application support data (with protection for critical system settings)
    echo -n "  ${BLUE}🔍${NC} Scanning application data..."
    if ls ~/Library/Application\ Support/com.* >/dev/null 2>&1; then
        for support_dir in ~/Library/Application\ Support/com.*; do
            [[ -d "$support_dir" ]] || continue
            local bundle_id=$(basename "$support_dir")
            # CRITICAL: Skip system-essential and protected app data
            if should_protect_data "$bundle_id"; then
                continue
            fi
            if ! grep -q "$bundle_id" "$installed_bundles" 2>/dev/null; then
                safe_clean "$support_dir" "Orphaned data: $bundle_id"
                found_orphaned=true
                ((data_count++))
            fi
        done
    fi
    # Also check for non-com.* folders that may contain user data
    for support_dir in ~/Library/Application\ Support/*; do
        [[ -d "$support_dir" ]] || continue
        local dir_name=$(basename "$support_dir")
        # Skip if it starts with com. (already processed) or is in dot directories
        [[ "$dir_name" == com.* || "$dir_name" == .* ]] && continue
        # CRITICAL: Protect important data folders (JetBrains, database tools, etc.)
        if should_protect_data "$dir_name"; then
            continue
        fi
        # Only clean if significant size and looks like app data, but be conservative
        # Skip common system/user folders
        case "$dir_name" in
            "CrashReporter"|"AddressBook"|"CallHistoryDB"|"CallHistoryTransactions"|\
            "CloudDocs"|"icdd"|"IdentityServices"|"Mail"|"CallServices"|\
            "com.apple."*|"Adobe"|"Google"|"Mozilla"|"Netscape"|"Yahoo"|\
            "AddressBook"|"iCloud"|"iLifeMediaBrowser"|"MobileSync"|\
            "CallHistory"|"FaceTime"|"Twitter")
                # System or commonly used folders, skip
                continue
                ;;
        esac
    done
    echo " ${GREEN}✓${NC} Complete ($data_count removed)"

    # Check for orphaned preferences (with protection for critical system settings)
    echo -n "  ${BLUE}🔍${NC} Scanning preference files..."
    if ls ~/Library/Preferences/com.*.plist >/dev/null 2>&1; then
        for pref_file in ~/Library/Preferences/com.*.plist; do
            [[ -f "$pref_file" ]] || continue
            local bundle_id=$(basename "$pref_file" .plist)
            # CRITICAL: Skip system-essential and protected app preferences
            if should_protect_data "$bundle_id"; then
                continue
            fi
            if ! grep -q "$bundle_id" "$installed_bundles" 2>/dev/null; then
                safe_clean "$pref_file" "Orphaned preference: $bundle_id"
                found_orphaned=true
                ((pref_count++))
            fi
        done
    fi
    echo " ${GREEN}✓${NC} Complete ($pref_count removed)"

    # Clean up temp file
    rm -f "$installed_bundles"

    # Clean test data
    safe_clean ~/Library/Application\ Support/TestApp* "Test app data"
    safe_clean ~/Library/Application\ Support/MyApp/* "Test app data"
    safe_clean ~/Library/Application\ Support/GitHub*/* "GitHub test data"
    safe_clean ~/Library/Application\ Support/Twitter*/* "Twitter test data"
    safe_clean ~/Library/Application\ Support/TestNoValue/* "Test data"
    safe_clean ~/Library/Application\ Support/Wk*/* "Test data"

    end_section

    # ===== 13. Apple Silicon optimizations =====
    if [[ "$IS_M_SERIES" == "true" ]]; then
        start_section "Apple Silicon optimizations"
        safe_clean /Library/Apple/usr/share/rosetta/rosetta_update_bundle "Rosetta 2 cache"
        safe_clean ~/Library/Caches/com.apple.rosetta.update "Rosetta 2 user cache"
        safe_clean ~/Library/Caches/com.apple.amp.mediasevicesd "Apple Silicon media service cache"
        safe_clean ~/Library/Caches/com.apple.bird.lsuseractivity "User activity cache"
        end_section
    fi

    # System cleanup was moved to the beginning (right after password verification)

    # ===== 14. iOS device backups =====
    start_section "iOS device backups"
    backup_dir="$HOME/Library/Application Support/MobileSync/Backup"
    if [[ -d "$backup_dir" ]] && find "$backup_dir" -mindepth 1 -maxdepth 1 | read -r _; then
        backup_kb=$(du -sk "$backup_dir" 2>/dev/null | awk '{print $1}')
        if [[ -n "${backup_kb:-}" && "$backup_kb" -gt 102400 ]]; then # >100MB
            backup_human=$(du -sh "$backup_dir" 2>/dev/null | awk '{print $1}')
            note_activity
            echo -e "  ${BLUE}💾${NC} Found ${GREEN}${backup_human}${NC} iOS backups"
            echo -e "  ${YELLOW}💡${NC} You can delete them manually: ${backup_dir}"
        fi
    fi
    end_section

    # ===== Final summary =====
    space_after=$(df / | tail -1 | awk '{print $4}')
    space_freed_kb=$((space_after - space_before))

    echo ""
    echo "===================================================================="
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "🧪 DRY RUN COMPLETE!"
    else
        echo "🎉 CLEANUP COMPLETE!"
    fi

    if [[ $total_size_cleaned -gt 0 ]]; then
        local freed_gb=$(echo "$total_size_cleaned" | awk '{printf "%.2f", $1/1024/1024}')
        if [[ "$DRY_RUN" == "true" ]]; then
            echo "💾 Potential reclaimable space: ${GREEN}${freed_gb}GB${NC} (no changes made) | Free space now: $(get_free_space)"
        else
            echo "💾 Space freed: ${GREEN}${freed_gb}GB${NC} | Free space now: $(get_free_space)"
        fi

        if [[ "$DRY_RUN" != "true" ]]; then
            # Add some context when actually freed
            if [[ $(echo "$freed_gb" | awk '{print ($1 >= 1) ? 1 : 0}') -eq 1 ]]; then
                local movies=$(echo "$freed_gb" | awk '{printf "%.0f", $1/4.5}')
                if [[ $movies -gt 0 ]]; then
                    echo "🎬 That's like ~$movies 4K movies worth of space!"
                fi
            fi
        fi
    else
        if [[ "$DRY_RUN" == "true" ]]; then
            echo "💾 No significant reclaimable space detected (already clean) | Free space: $(get_free_space)"
        else
            echo "💾 No significant space was freed (system was already clean) | Free space: $(get_free_space)"
        fi
    fi
    
    if [[ $files_cleaned -gt 0 && $total_items -gt 0 ]]; then
        echo "📊 Files cleaned: $files_cleaned | Categories processed: $total_items"
    elif [[ $files_cleaned -gt 0 ]]; then
        echo "📊 Files cleaned: $files_cleaned"
    elif [[ $total_items -gt 0 ]]; then
        echo "🗂️ Categories processed: $total_items"
    fi

    if [[ "$SYSTEM_CLEAN" != "true" ]]; then
        echo ""
        echo -e "${BLUE}💡 For deeper cleanup, run with admin password next time${NC}"
    fi

    echo "===================================================================="
}

# Cleanup function - restore cursor on exit
cleanup() {
    # Restore cursor
    show_cursor
    # Kill any background processes
    if [[ -n "${SUDO_KEEPALIVE_PID:-}" ]]; then
        kill "$SUDO_KEEPALIVE_PID" 2>/dev/null || true
    fi
    if [[ -n "${SPINNER_PID:-}" ]]; then
        kill "$SPINNER_PID" 2>/dev/null || true
    fi
    exit "${1:-0}"
}

# Set trap for cleanup on exit
trap cleanup EXIT INT TERM

main() {
    # Parse args (only dry-run and help for minimal impact)
    for arg in "$@"; do
        case "$arg" in
            "--dry-run"|"-n")
                DRY_RUN=true
                ;;
            "--whitelist")
                echo "Active whitelist patterns:"; for w in "${WHITELIST_PATTERNS[@]}"; do echo "  $w"; done; exit 0
                ;;
            "--help"|"-h")
                echo "Mole - Deeper system cleanup"
                echo "Usage: clean.sh [options]"
                echo ""
                echo "Options:"
                echo "  --help, -h        Show this help"
                echo "  --dry-run, -n     Preview what would be cleaned without deleting"
                echo "  --whitelist       Show active whitelist patterns"
                echo ""
                echo "Interactive cleanup with smart password handling"
                echo ""
                exit 0
                ;;
        esac
    done

    hide_cursor
    start_cleanup
    perform_cleanup
    show_cursor
}

main "$@"
