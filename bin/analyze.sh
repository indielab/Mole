#!/bin/bash
# Mole - Disk Space Analyzer Module
# Fast disk analysis with mdfind + du hybrid approach

set -euo pipefail

# Get script directory for sourcing libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$(dirname "$SCRIPT_DIR")/lib"

# Source required libraries
# shellcheck source=../lib/common.sh
source "$LIB_DIR/common.sh"

# Constants
readonly CACHE_DIR="${HOME}/.config/mole/cache"
readonly TEMP_PREFIX="/tmp/mole_analyze_$$"
readonly MIN_LARGE_FILE_SIZE="1000000000"    # 1GB
readonly MIN_MEDIUM_FILE_SIZE="100000000"     # 100MB
readonly MIN_SMALL_FILE_SIZE="10000000"       # 10MB

# Global state
declare -a SCAN_RESULTS=()
declare -a DIR_RESULTS=()
declare -a LARGE_FILES=()
declare SCAN_PID=""
declare TOTAL_SIZE=0
declare CURRENT_PATH="$HOME"
declare CURRENT_DEPTH=1

# UI State
declare CURSOR_POS=0
declare SORT_MODE="size"  # size, name, time
declare VIEW_MODE="overview"  # overview, detail, files

# Cleanup on exit
cleanup() {
    show_cursor
    rm -f "$TEMP_PREFIX"* 2>/dev/null || true
    if [[ -n "$SCAN_PID" ]] && kill -0 "$SCAN_PID" 2>/dev/null; then
        kill "$SCAN_PID" 2>/dev/null || true
    fi
}

trap cleanup EXIT INT TERM

# ============================================================================
# Scanning Functions
# ============================================================================

# Fast scan using mdfind for large files
scan_large_files() {
    local target_path="$1"
    local output_file="$2"

    if ! command -v mdfind &>/dev/null; then
        return 1
    fi

    # Scan files > 1GB
    mdfind -onlyin "$target_path" "kMDItemFSSize > $MIN_LARGE_FILE_SIZE" 2>/dev/null | \
        while IFS= read -r file; do
            if [[ -f "$file" ]]; then
                local size=$(stat -f%z "$file" 2>/dev/null || echo "0")
                echo "$size|$file"
            fi
        done | sort -t'|' -k1 -rn > "$output_file"
}

# Scan medium files (100MB - 1GB)
scan_medium_files() {
    local target_path="$1"
    local output_file="$2"

    if ! command -v mdfind &>/dev/null; then
        return 1
    fi

    mdfind -onlyin "$target_path" \
        "kMDItemFSSize > $MIN_MEDIUM_FILE_SIZE && kMDItemFSSize < $MIN_LARGE_FILE_SIZE" 2>/dev/null | \
        while IFS= read -r file; do
            if [[ -f "$file" ]]; then
                local size=$(stat -f%z "$file" 2>/dev/null || echo "0")
                echo "$size|$file"
            fi
        done | sort -t'|' -k1 -rn > "$output_file"
}

# Scan top-level directories with du (optimized with parallel)
scan_directories() {
    local target_path="$1"
    local output_file="$2"
    local depth="${3:-1}"

    # Check if we can use parallel processing
    if command -v xargs &>/dev/null && [[ $depth -eq 1 ]]; then
        # Fast parallel scan for depth 1
        find "$target_path" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null | \
            xargs -0 -P 4 -I {} du -sk {} 2>/dev/null | \
            sort -rn | \
            while IFS=$'\t' read -r size path; do
                echo "$((size * 1024))|$path"
            done > "$output_file"
    else
        # Standard du scan
        du -d "$depth" -k "$target_path" 2>/dev/null | \
            sort -rn | \
            while IFS=$'\t' read -r size path; do
                # Skip if path is the target itself at depth > 0
                if [[ "$path" != "$target_path" ]]; then
                    echo "$((size * 1024))|$path"
                fi
            done > "$output_file"
    fi
}

# Aggregate files by directory
aggregate_by_directory() {
    local file_list="$1"
    local output_file="$2"

    awk -F'|' '{
        path = $2
        size = $1
        # Get parent directory
        n = split(path, parts, "/")
        dir = ""
        for(i=1; i<n; i++) {
            dir = dir parts[i] "/"
        }
        if(dir) {
            dir_count[dir]++
            dir_size[dir] += size
        }
    }
    END {
        for(dir in dir_count) {
            printf "%d|%s|%d\n", dir_size[dir], dir, dir_count[dir]
        }
    }' "$file_list" | sort -t'|' -k1 -rn > "$output_file"
}

# Get cache file path for a directory
get_cache_file() {
    local target_path="$1"
    local path_hash=$(echo "$target_path" | md5 2>/dev/null || echo "$target_path" | shasum | cut -d' ' -f1)
    echo "$CACHE_DIR/scan_${path_hash}.cache"
}

# Check if cache is valid (less than 1 hour old)
is_cache_valid() {
    local cache_file="$1"
    local max_age="${2:-3600}"  # Default 1 hour

    if [[ ! -f "$cache_file" ]]; then
        return 1
    fi

    local cache_age=$(($(date +%s) - $(stat -f%m "$cache_file" 2>/dev/null || echo 0)))
    if [[ $cache_age -lt $max_age ]]; then
        return 0
    fi

    return 1
}

# Save scan results to cache
save_to_cache() {
    local cache_file="$1"
    local temp_large="$TEMP_PREFIX.large"
    local temp_medium="$TEMP_PREFIX.medium"
    local temp_dirs="$TEMP_PREFIX.dirs"
    local temp_agg="$TEMP_PREFIX.agg"

    # Create cache directory
    mkdir -p "$(dirname "$cache_file")" 2>/dev/null || return 1

    # Bundle all scan results into cache file
    {
        echo "### LARGE ###"
        [[ -f "$temp_large" ]] && cat "$temp_large"
        echo "### MEDIUM ###"
        [[ -f "$temp_medium" ]] && cat "$temp_medium"
        echo "### DIRS ###"
        [[ -f "$temp_dirs" ]] && cat "$temp_dirs"
        echo "### AGG ###"
        [[ -f "$temp_agg" ]] && cat "$temp_agg"
    } > "$cache_file" 2>/dev/null
}

# Load scan results from cache
load_from_cache() {
    local cache_file="$1"
    local temp_large="$TEMP_PREFIX.large"
    local temp_medium="$TEMP_PREFIX.medium"
    local temp_dirs="$TEMP_PREFIX.dirs"
    local temp_agg="$TEMP_PREFIX.agg"

    local section=""
    while IFS= read -r line; do
        case "$line" in
            "### LARGE ###") section="large" ;;
            "### MEDIUM ###") section="medium" ;;
            "### DIRS ###") section="dirs" ;;
            "### AGG ###") section="agg" ;;
            *)
                case "$section" in
                    "large") echo "$line" >> "$temp_large" ;;
                    "medium") echo "$line" >> "$temp_medium" ;;
                    "dirs") echo "$line" >> "$temp_dirs" ;;
                    "agg") echo "$line" >> "$temp_agg" ;;
                esac
                ;;
        esac
    done < "$cache_file"
}

# Main scan coordinator
perform_scan() {
    local target_path="$1"
    local force_rescan="${2:-false}"

    # Check cache first
    local cache_file=$(get_cache_file "$target_path")
    if [[ "$force_rescan" != "true" ]] && is_cache_valid "$cache_file" 3600; then
        log_info "Loading cached results for $target_path..."
        load_from_cache "$cache_file"
        log_success "Cache loaded!"
        return 0
    fi

    log_info "Analyzing disk space in $target_path..."
    echo ""

    # Create temp files
    local temp_large="$TEMP_PREFIX.large"
    local temp_medium="$TEMP_PREFIX.medium"
    local temp_dirs="$TEMP_PREFIX.dirs"
    local temp_agg="$TEMP_PREFIX.agg"

    # Start parallel scans
    {
        scan_large_files "$target_path" "$temp_large" &
        scan_medium_files "$target_path" "$temp_medium" &
        scan_directories "$target_path" "$temp_dirs" "$CURRENT_DEPTH" &
        wait
    } &
    SCAN_PID=$!

    # Show spinner with progress while scanning
    local spinner_chars="⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏"
    local i=0
    local elapsed=0
    hide_cursor

    # Progress messages (short and dynamic)
    local messages=(
        "Finding large files"
        "Scanning directories"
        "Calculating sizes"
        "Finishing up"
    )
    local msg_idx=0

    while kill -0 "$SCAN_PID" 2>/dev/null; do
        # Show different messages based on elapsed time
        local current_msg=""
        if [[ $elapsed -lt 5 ]]; then
            current_msg="${messages[0]}"
        elif [[ $elapsed -lt 15 ]]; then
            current_msg="${messages[1]}"
        elif [[ $elapsed -lt 25 ]]; then
            current_msg="${messages[2]}"
        else
            current_msg="${messages[3]}"
        fi

        printf "\r${BLUE}%s${NC} %s" \
            "${spinner_chars:$i:1}" "$current_msg"

        i=$(( (i + 1) % 10 ))
        ((elapsed++))
        sleep 0.1
    done
    wait "$SCAN_PID" 2>/dev/null || true
    printf "\r%80s\r" ""  # Clear spinner line
    show_cursor

    # Aggregate results
    if [[ -f "$temp_large" ]] && [[ -s "$temp_large" ]]; then
        aggregate_by_directory "$temp_large" "$temp_agg"
    fi

    # Save to cache
    save_to_cache "$cache_file"

    log_success "Scan complete!"
}

# ============================================================================
# Visualization Functions
# ============================================================================

# Generate progress bar
generate_bar() {
    local current="$1"
    local max="$2"
    local width="${3:-20}"

    if [[ "$max" -eq 0 ]]; then
        printf "%${width}s" "" | tr ' ' '░'
        return
    fi

    local filled=$((current * width / max))
    local empty=$((width - filled))

    # Ensure non-negative
    [[ $filled -lt 0 ]] && filled=0
    [[ $empty -lt 0 ]] && empty=0

    local bar=""
    if [[ $filled -gt 0 ]]; then
        bar=$(printf "%${filled}s" "" | tr ' ' '█')
    fi
    if [[ $empty -gt 0 ]]; then
        bar="${bar}$(printf "%${empty}s" "" | tr ' ' '░')"
    fi

    echo "$bar"
}

# Calculate percentage
calc_percentage() {
    local part="$1"
    local total="$2"

    if [[ "$total" -eq 0 ]]; then
        echo "0"
        return
    fi

    echo "$part" "$total" | awk '{printf "%.1f", ($1/$2)*100}'
}

# Display large files summary (compact version)
display_large_files_compact() {
    local temp_large="$TEMP_PREFIX.large"

    if [[ ! -f "$temp_large" ]] || [[ ! -s "$temp_large" ]]; then
        return
    fi

    log_header "📊 Top Large Files"
    echo ""

    local count=0
    local total_size=0
    local total_count=$(wc -l < "$temp_large" | tr -d ' ')

    # Calculate total size
    while IFS='|' read -r size path; do
        ((total_size += size))
    done < "$temp_large"

    # Show top 5 only
    while IFS='|' read -r size path; do
        if [[ $count -ge 5 ]]; then
            break
        fi

        local human_size=$(bytes_to_human "$size")
        local filename=$(basename "$path")
        local dirname=$(basename "$(dirname "$path")")

        printf "  ${GREEN}%-8s${NC} 📄 %-40s ${GRAY}%s${NC}\n" \
            "$human_size" "${filename:0:40}" "$dirname"

        ((count++))
    done < "$temp_large"

    echo ""
    local total_human=$(bytes_to_human "$total_size")
    echo "  ${GRAY}Found $total_count large files (>1GB), totaling $total_human${NC}"
    echo ""
}

# Display large files summary (full version)
display_large_files() {
    local temp_large="$TEMP_PREFIX.large"

    if [[ ! -f "$temp_large" ]] || [[ ! -s "$temp_large" ]]; then
        log_header "📊 Large Files (>1GB)"
        echo ""
        echo "  ${GRAY}No files larger than 1GB found${NC}"
        echo ""
        return
    fi

    log_header "📊 Large Files (>1GB)"
    echo ""

    local count=0
    local max_size=0

    # Get max size for progress bar
    max_size=$(head -1 "$temp_large" | cut -d'|' -f1)
    [[ -z "$max_size" ]] && max_size=1

    while IFS='|' read -r size path; do
        if [[ $count -ge 10 ]]; then
            break
        fi

        local human_size=$(bytes_to_human "$size")
        local percentage=$(calc_percentage "$size" "$max_size")
        local bar=$(generate_bar "$size" "$max_size" 20)
        local filename=$(basename "$path")
        local dirname=$(dirname "$path" | sed "s|^$HOME|~|")

        printf "  %s [${GREEN}%s${NC}] %7s\n" "$bar" "$human_size" ""
        printf "    📄 %s\n" "$filename"
        printf "    ${GRAY}%s${NC}\n\n" "$dirname"

        ((count++))
    done < "$temp_large"

    # Show total count
    local total_count=$(wc -l < "$temp_large" | tr -d ' ')
    if [[ $total_count -gt 10 ]]; then
        echo "  ${GRAY}... and $((total_count - 10)) more files${NC}"
        echo ""
    fi
}

# Display directory summary (compact version)
display_directories_compact() {
    local temp_dirs="$TEMP_PREFIX.dirs"

    if [[ ! -f "$temp_dirs" ]] || [[ ! -s "$temp_dirs" ]]; then
        return
    fi

    log_header "📁 Top Directories"
    echo ""

    local count=0
    local total_size=0

    # Calculate total
    while IFS='|' read -r size path; do
        ((total_size += size))
    done < "$temp_dirs"
    [[ $total_size -eq 0 ]] && total_size=1

    # Show top 8 directories in compact format
    while IFS='|' read -r size path; do
        if [[ $count -ge 8 ]]; then
            break
        fi

        local human_size=$(bytes_to_human "$size")
        local percentage=$(calc_percentage "$size" "$total_size")
        local dirname=$(basename "$path")

        # Simple bar (10 chars)
        local bar_width=10
        local percentage_int=${percentage%.*}  # Remove decimal part
        local filled=$((percentage_int * bar_width / 100))
        [[ $filled -gt $bar_width ]] && filled=$bar_width
        [[ $filled -lt 0 ]] && filled=0
        local empty=$((bar_width - filled))
        [[ $empty -lt 0 ]] && empty=0
        local bar=""
        if [[ $filled -gt 0 ]]; then
            bar=$(printf "%${filled}s" "" | tr ' ' '█')
        fi
        if [[ $empty -gt 0 ]]; then
            bar="${bar}$(printf "%${empty}s" "" | tr ' ' '░')"
        fi

        printf "  ${BLUE}%-8s${NC} %s ${GRAY}%3s%%${NC} 📁 %s\n" \
            "$human_size" "$bar" "$percentage" "$dirname"

        ((count++))
    done < "$temp_dirs"
    echo ""
}

# Display directory summary (full version)
display_directories() {
    local temp_dirs="$TEMP_PREFIX.dirs"

    if [[ ! -f "$temp_dirs" ]] || [[ ! -s "$temp_dirs" ]]; then
        return
    fi

    log_header "📁 Top Directories"
    echo ""

    local count=0
    local max_size=0
    local total_size=0

    # Calculate total and max for percentages
    max_size=$(head -1 "$temp_dirs" | cut -d'|' -f1)
    [[ -z "$max_size" ]] && max_size=1

    while IFS='|' read -r size path; do
        ((total_size += size))
    done < "$temp_dirs"

    [[ $total_size -eq 0 ]] && total_size=1

    # Display directories
    while IFS='|' read -r size path; do
        if [[ $count -ge 15 ]]; then
            break
        fi

        local human_size=$(bytes_to_human "$size")
        local percentage=$(calc_percentage "$size" "$total_size")
        local bar=$(generate_bar "$size" "$max_size" 20)
        local display_path=$(echo "$path" | sed "s|^$HOME|~|")
        local dirname=$(basename "$path")

        printf "  %s [${BLUE}%s${NC}] %5s%%\n" "$bar" "$human_size" "$percentage"
        printf "    📁 %s\n\n" "$display_path"

        ((count++))
    done < "$temp_dirs"
}

# Display hotspot directories (many large files)
display_hotspots() {
    local temp_agg="$TEMP_PREFIX.agg"

    if [[ ! -f "$temp_agg" ]] || [[ ! -s "$temp_agg" ]]; then
        return
    fi

    log_header "🔥 Hotspot Directories (High File Concentration)"
    echo ""

    local count=0
    while IFS='|' read -r size path file_count; do
        if [[ $count -ge 8 ]]; then
            break
        fi

        local human_size=$(bytes_to_human "$size")
        local display_path=$(echo "$path" | sed "s|^$HOME|~|")

        printf "  📍 %s\n" "$display_path"
        printf "     ${GREEN}%s${NC} in ${YELLOW}%d${NC} large files\n\n" \
            "$human_size" "$file_count"

        ((count++))
    done < "$temp_agg"
}

# Display smart cleanup suggestions (compact version)
display_cleanup_suggestions_compact() {
    local suggestions_count=0
    local top_suggestion=""
    local potential_space=0
    local action_command=""

    # Check common cache locations (only if analyzing Library/Caches or system paths)
    if [[ "$CURRENT_PATH" == "$HOME/Library/Caches"* ]] || [[ "$CURRENT_PATH" == "$HOME/Library"* ]]; then
        if [[ -d "$HOME/Library/Caches" ]]; then
            local cache_size=$(du -sk "$HOME/Library/Caches" 2>/dev/null | cut -f1)
            if [[ $cache_size -gt 1048576 ]]; then  # > 1GB
                local human=$(bytes_to_human $((cache_size * 1024)))
                top_suggestion="Clear app caches ($human)"
                action_command="mole clean"
                ((potential_space += cache_size * 1024))
                ((suggestions_count++))
            fi
        fi
    fi

    # Check Downloads folder (only if analyzing Downloads)
    if [[ "$CURRENT_PATH" == "$HOME/Downloads"* ]]; then
        local old_files=$(find "$CURRENT_PATH" -type f -mtime +90 2>/dev/null | wc -l | tr -d ' ')
        if [[ $old_files -gt 0 ]]; then
            [[ -z "$top_suggestion" ]] && top_suggestion="$old_files files older than 90 days found"
            [[ -z "$action_command" ]] && action_command="manually review old files"
            ((suggestions_count++))
        fi
    fi

    # Check for large disk images in current path
    if command -v mdfind &>/dev/null; then
        local dmg_count=$(mdfind -onlyin "$CURRENT_PATH" \
            "kMDItemFSSize > 500000000 && kMDItemDisplayName == '*.dmg'" 2>/dev/null | wc -l | tr -d ' ')
        if [[ $dmg_count -gt 0 ]]; then
            local dmg_size=$(mdfind -onlyin "$CURRENT_PATH" \
                "kMDItemFSSize > 500000000 && kMDItemDisplayName == '*.dmg'" 2>/dev/null | \
                xargs stat -f%z 2>/dev/null | awk '{sum+=$1} END {print sum}')
            local dmg_human=$(bytes_to_human "$dmg_size")
            [[ -z "$top_suggestion" ]] && top_suggestion="$dmg_count DMG files ($dmg_human) can be removed"
            [[ -z "$action_command" ]] && action_command="manually delete DMG files"
            ((potential_space += dmg_size))
            ((suggestions_count++))
        fi
    fi

    # Check Xcode (only if in developer paths)
    if [[ "$CURRENT_PATH" == "$HOME/Library/Developer"* ]] && [[ -d "$HOME/Library/Developer/Xcode/DerivedData" ]]; then
        local xcode_size=$(du -sk "$HOME/Library/Developer/Xcode/DerivedData" 2>/dev/null | cut -f1)
        if [[ $xcode_size -gt 10485760 ]]; then
            local xcode_human=$(bytes_to_human $((xcode_size * 1024)))
            [[ -z "$top_suggestion" ]] && top_suggestion="Xcode cache ($xcode_human) can be cleared"
            [[ -z "$action_command" ]] && action_command="mole clean"
            ((potential_space += xcode_size * 1024))
            ((suggestions_count++))
        fi
    fi

    # Check for duplicates in current path
    if command -v mdfind &>/dev/null; then
        local dup_count=$(mdfind -onlyin "$CURRENT_PATH" "kMDItemFSSize > 10000000" 2>/dev/null | \
            xargs -I {} stat -f "%z" {} 2>/dev/null | sort | uniq -d | wc -l | tr -d ' ')
        if [[ $dup_count -gt 5 ]]; then
            [[ -z "$top_suggestion" ]] && top_suggestion="$dup_count potential duplicate files detected"
            ((suggestions_count++))
        fi
    fi

    if [[ $suggestions_count -gt 0 ]]; then
        log_header "💡 Quick Insights"
        echo ""
        echo "  ${YELLOW}✨ $top_suggestion${NC}"
        if [[ $suggestions_count -gt 1 ]]; then
            echo "  ${GRAY}... and $((suggestions_count - 1)) more insights${NC}"
        fi
        if [[ $potential_space -gt 0 ]]; then
            local space_human=$(bytes_to_human "$potential_space")
            echo "  ${GREEN}Potential recovery: ~$space_human${NC}"
        fi
        echo ""
        if [[ -n "$action_command" ]]; then
            if [[ "$action_command" == "mole clean" ]]; then
                echo "  ${GRAY}→ Run${NC} ${YELLOW}mole clean${NC} ${GRAY}to cleanup system files${NC}"
            else
                echo "  ${GRAY}→ Review and ${NC}${YELLOW}$action_command${NC}"
            fi
        fi
        echo ""
    fi
}

# Display smart cleanup suggestions (full version)
display_cleanup_suggestions() {
    log_header "💡 Smart Cleanup Suggestions"
    echo ""

    local suggestions=()

    # Check common cache locations
    if [[ -d "$HOME/Library/Caches" ]]; then
        local cache_size=$(du -sk "$HOME/Library/Caches" 2>/dev/null | cut -f1)
        if [[ $cache_size -gt 1048576 ]]; then  # > 1GB
            local human=$(bytes_to_human $((cache_size * 1024)))
            suggestions+=("  🗑️  Clear application caches: $human")
        fi
    fi

    # Check Downloads folder
    if [[ -d "$HOME/Downloads" ]]; then
        local old_files=$(find "$HOME/Downloads" -type f -mtime +90 2>/dev/null | wc -l | tr -d ' ')
        if [[ $old_files -gt 0 ]]; then
            suggestions+=("  📥 Clean old downloads: $old_files files older than 90 days")
        fi
    fi

    # Check for large disk images
    if command -v mdfind &>/dev/null; then
        local dmg_count=$(mdfind -onlyin "$HOME" \
            "kMDItemFSSize > 500000000 && kMDItemDisplayName == '*.dmg'" 2>/dev/null | wc -l | tr -d ' ')
        if [[ $dmg_count -gt 0 ]]; then
            suggestions+=("  💿 Remove disk images: $dmg_count DMG files >500MB")
        fi
    fi

    # Check Xcode derived data
    if [[ -d "$HOME/Library/Developer/Xcode/DerivedData" ]]; then
        local xcode_size=$(du -sk "$HOME/Library/Developer/Xcode/DerivedData" 2>/dev/null | cut -f1)
        if [[ $xcode_size -gt 10485760 ]]; then  # > 10GB
            local human=$(bytes_to_human $((xcode_size * 1024)))
            suggestions+=("  🔨 Clear Xcode cache: $human")
        fi
    fi

    # Check iOS device backups
    if [[ -d "$HOME/Library/Application Support/MobileSync/Backup" ]]; then
        local backup_size=$(du -sk "$HOME/Library/Application Support/MobileSync/Backup" 2>/dev/null | cut -f1)
        if [[ $backup_size -gt 5242880 ]]; then  # > 5GB
            local human=$(bytes_to_human $((backup_size * 1024)))
            suggestions+=("  📱 Review iOS backups: $human")
        fi
    fi

    # Check for duplicate files (by size, quick heuristic)
    if command -v mdfind &>/dev/null; then
        local temp_dup="$TEMP_PREFIX.dup_check"
        mdfind -onlyin "$CURRENT_PATH" "kMDItemFSSize > 10000000" 2>/dev/null | \
            xargs -I {} stat -f "%z" {} 2>/dev/null | \
            sort | uniq -d | wc -l | tr -d ' ' > "$temp_dup" 2>/dev/null || echo "0" > "$temp_dup"
        local dup_count=$(cat "$temp_dup" 2>/dev/null || echo "0")
        if [[ $dup_count -gt 5 ]]; then
            suggestions+=("  📋 Possible duplicates: $dup_count size matches in large files (>10MB)")
        fi
    fi

    # Display suggestions
    if [[ ${#suggestions[@]} -gt 0 ]]; then
        printf '%s\n' "${suggestions[@]}"
        echo ""
        echo "  ${YELLOW}Tip:${NC} Run 'mole clean' to perform cleanup operations"
    else
        echo "  ${GREEN}✓${NC} No obvious cleanup opportunities found"
    fi
    echo ""
}

# Display overall disk situation summary
display_disk_summary() {
    local temp_large="$TEMP_PREFIX.large"
    local temp_dirs="$TEMP_PREFIX.dirs"

    # Calculate stats
    local total_large_size=0
    local total_large_count=0
    local total_dirs_size=0
    local total_dirs_count=0

    if [[ -f "$temp_large" ]]; then
        total_large_count=$(wc -l < "$temp_large" 2>/dev/null | tr -d ' ')
        while IFS='|' read -r size path; do
            ((total_large_size += size))
        done < "$temp_large"
    fi

    if [[ -f "$temp_dirs" ]]; then
        total_dirs_count=$(wc -l < "$temp_dirs" 2>/dev/null | tr -d ' ')
        while IFS='|' read -r size path; do
            ((total_dirs_size += size))
        done < "$temp_dirs"
    fi

    log_header "💾 Disk Situation"

    local target_display=$(echo "$CURRENT_PATH" | sed "s|^$HOME|~|")
    echo "  ${BLUE}Scanning:${NC} $target_display | ${BLUE}Free:${NC} $(get_free_space)"

    if [[ $total_large_count -gt 0 ]]; then
        local large_human=$(bytes_to_human "$total_large_size")
        echo "  ${BLUE}Large Files:${NC} $total_large_count files ($large_human) | ${BLUE}Total:${NC} $(bytes_to_human "$total_dirs_size") in $total_dirs_count dirs"
    elif [[ $total_dirs_size -gt 0 ]]; then
        echo "  ${BLUE}Total Scanned:${NC} $(bytes_to_human "$total_dirs_size") across $total_dirs_count directories"
    fi
    echo ""
}

# Get file type icon and description
get_file_info() {
    local path="$1"
    local ext="${path##*.}"
    local icon=""
    local type=""

    case "$ext" in
        dmg|iso|pkg) icon="📦" ; type="Installer" ;;
        mov|mp4|avi|mkv|webm) icon="🎬" ; type="Video" ;;
        zip|tar|gz|rar|7z) icon="🗜️" ; type="Archive" ;;
        pdf) icon="📄" ; type="Document" ;;
        jpg|jpeg|png|gif|heic) icon="🖼️" ; type="Image" ;;
        key|ppt|pptx) icon="📊" ; type="Slides" ;;
        log) icon="📝" ; type="Log" ;;
        app) icon="⚙️" ; type="App" ;;
        *) icon="📄" ; type="File" ;;
    esac

    echo "$icon|$type"
}

# Get file age in human readable format
get_file_age() {
    local path="$1"
    if [[ ! -f "$path" ]]; then
        echo "N/A"
        return
    fi

    local mtime=$(stat -f%m "$path" 2>/dev/null || echo "0")
    local now=$(date +%s)
    local diff=$((now - mtime))
    local days=$((diff / 86400))

    if [[ $days -lt 1 ]]; then
        echo "Today"
    elif [[ $days -eq 1 ]]; then
        echo "1 day"
    elif [[ $days -lt 30 ]]; then
        echo "${days}d"
    elif [[ $days -lt 365 ]]; then
        local months=$((days / 30))
        echo "${months}mo"
    else
        local years=$((days / 365))
        echo "${years}yr"
    fi
}

# Display large files in compact table format
display_large_files_table() {
    local temp_large="$TEMP_PREFIX.large"

    if [[ ! -f "$temp_large" ]] || [[ ! -s "$temp_large" ]]; then
        return
    fi

    log_header "🎯 What's Taking Up Space"

    # Table header
    printf "  %-4s  %-10s  %-8s  %s\n" "TYPE" "SIZE" "AGE" "FILE"
    printf "  %s\n" "$(printf '%.0s─' {1..80})"

    local count=0
    while IFS='|' read -r size path; do
        if [[ $count -ge 20 ]]; then
            break
        fi

        local human_size=$(bytes_to_human "$size")
        local filename=$(basename "$path")
        local ext="${filename##*.}"
        local age=$(get_file_age "$path")

        # Get file info
        local info=$(get_file_info "$path")
        local icon="${info%|*}"

        # Truncate filename if too long
        if [[ ${#filename} -gt 50 ]]; then
            filename="${filename:0:47}..."
        fi

        # Color based on file type
        local color=""
        case "$ext" in
            dmg|iso|pkg) color="${RED}" ;;
            mov|mp4|avi|mkv|webm|zip|tar|gz|rar|7z) color="${YELLOW}" ;;
            log) color="${GRAY}" ;;
            *) color="${NC}" ;;
        esac

        printf "  %b%-4s  %-10s  %-8s  %s${NC}\n" \
            "$color" "$icon" "$human_size" "$age" "$filename"

        ((count++))
    done < "$temp_large"

    local total=$(wc -l < "$temp_large" | tr -d ' ')
    if [[ $total -gt 20 ]]; then
        echo "  ${GRAY}... $((total - 20)) more files${NC}"
    fi
    echo ""
}

# Display unified directory view in table format
display_unified_directories() {
    local temp_dirs="$TEMP_PREFIX.dirs"

    if [[ ! -f "$temp_dirs" ]] || [[ ! -s "$temp_dirs" ]]; then
        return
    fi

    # Calculate total
    local total_size=0
    while IFS='|' read -r size path; do
        ((total_size += size))
    done < "$temp_dirs"
    [[ $total_size -eq 0 ]] && total_size=1

    echo "  ${YELLOW}Top Directories:${NC}"

    # Table header
    printf "  %-30s  %5s  %10s  %s\n" "DIRECTORY" "%" "SIZE" "CHART"
    printf "  %s\n" "$(printf '%.0s─' {1..75})"

    # Show top 10 directories
    local count=0
    local chart_width=20
    while IFS='|' read -r size path; do
        if [[ $count -ge 10 ]]; then
            break
        fi

        local percentage=$((size * 100 / total_size))
        local bar_width=$((percentage * chart_width / 100))
        [[ $bar_width -lt 1 ]] && bar_width=1

        local dirname=$(basename "$path")
        local human_size=$(bytes_to_human "$size")

        # Build compact bar
        local bar=""
        if [[ $bar_width -gt 0 ]]; then
            bar=$(printf "%${bar_width}s" "" | tr ' ' '▓')
        fi
        local empty=$((chart_width - bar_width))
        if [[ $empty -gt 0 ]]; then
            bar="${bar}$(printf "%${empty}s" "" | tr ' ' '░')"
        fi

        # Truncate dirname if too long
        local display_name="$dirname"
        if [[ ${#dirname} -gt 28 ]]; then
            display_name="${dirname:0:25}..."
        fi

        # Color based on percentage
        local color="${NC}"
        if [[ $percentage -gt 50 ]]; then
            color="${RED}"
        elif [[ $percentage -gt 20 ]]; then
            color="${YELLOW}"
        else
            color="${BLUE}"
        fi

        printf "  %b%-30s  %4d%%  %10s  %s${NC}\n" \
            "$color" "$display_name" "$percentage" "$human_size" "$bar"

        ((count++))
    done < "$temp_dirs"
    echo ""
}

# Display context-aware recommendations
display_recommendations() {
    echo "  ${YELLOW}💡 Quick Actions:${NC}"

    if [[ "$CURRENT_PATH" == "$HOME/Downloads"* ]]; then
        echo "    → Delete ${RED}[Can Delete]${NC} items (installers/DMG)"
        echo "    → Review ${YELLOW}[Review]${NC} items (videos/archives)"
    elif [[ "$CURRENT_PATH" == "$HOME/Library"* ]]; then
        echo "    → Run ${GREEN}mole clean${NC} to clear caches safely"
        echo "    → Check Xcode/developer caches if applicable"
    else
        echo "    → Review ${RED}[Can Delete]${NC} and ${YELLOW}[Review]${NC} items"
        echo "    → Run ${GREEN}mole analyze ~/Library${NC} to check caches"
    fi
    echo ""
}

# Display space chart (visual tree map style)
display_space_chart() {
    local temp_dirs="$TEMP_PREFIX.dirs"

    if [[ ! -f "$temp_dirs" ]] || [[ ! -s "$temp_dirs" ]]; then
        return
    fi

    log_header "📊 Space Distribution"
    echo ""

    # Calculate total
    local total_size=0
    while IFS='|' read -r size path; do
        ((total_size += size))
    done < "$temp_dirs"
    [[ $total_size -eq 0 ]] && total_size=1

    # Show top 5 as blocks
    local count=0
    local chart_width=50
    while IFS='|' read -r size path; do
        if [[ $count -ge 5 ]]; then
            break
        fi

        local percentage=$((size * 100 / total_size))
        local bar_width=$((percentage * chart_width / 100))
        [[ $bar_width -lt 1 ]] && bar_width=1

        local dirname=$(basename "$path")
        local human_size=$(bytes_to_human "$size")

        # Build visual bar
        local bar=""
        if [[ $bar_width -gt 0 ]]; then
            bar=$(printf "%${bar_width}s" "" | tr ' ' '█')
        fi

        printf "  ${BLUE}%-15s${NC} %3d%% %s  %s\n" \
            "${dirname:0:15}" "$percentage" "$bar" "$human_size"

        ((count++))
    done < "$temp_dirs"
    echo ""
}

# Display recent large files (added in last 30 days)
display_recent_large_files() {
    log_header "🆕 Recent Large Files (Last 30 Days)"
    echo ""

    if ! command -v mdfind &>/dev/null; then
        echo "  ${YELLOW}Note: mdfind not available${NC}"
        echo ""
        return
    fi

    local temp_recent="$TEMP_PREFIX.recent"

    # Find files created in last 30 days, larger than 100MB
    mdfind -onlyin "$CURRENT_PATH" \
        "kMDItemFSSize > 100000000 && kMDItemContentCreationDate >= \$time.today(-30)" 2>/dev/null | \
        while IFS= read -r file; do
            if [[ -f "$file" ]]; then
                local size=$(stat -f%z "$file" 2>/dev/null || echo "0")
                local mtime=$(stat -f%m "$file" 2>/dev/null || echo "0")
                echo "$size|$mtime|$file"
            fi
        done | sort -t'|' -k1 -rn | head -10 > "$temp_recent"

    if [[ ! -s "$temp_recent" ]]; then
        echo "  ${GRAY}No large files created recently${NC}"
        echo ""
        return
    fi

    local count=0
    while IFS='|' read -r size mtime path; do
        local human_size=$(bytes_to_human "$size")
        local filename=$(basename "$path")
        local dirname=$(dirname "$path" | sed "s|^$HOME|~|")
        local days_ago=$(( ($(date +%s) - mtime) / 86400 ))

        printf "  📄 %s ${GRAY}(%s)${NC}\n" "$filename" "$human_size"
        printf "     ${GRAY}%s - %d days ago${NC}\n\n" "$dirname" "$days_ago"

        ((count++))
    done < "$temp_recent"
}

# ============================================================================
# Interactive Navigation
# ============================================================================

# Get list of subdirectories
get_subdirectories() {
    local target="$1"
    local temp_file="$2"

    find "$target" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | \
        while IFS= read -r dir; do
            local size=$(du -sk "$dir" 2>/dev/null | cut -f1)
            echo "$((size * 1024))|$dir"
        done | sort -t'|' -k1 -rn > "$temp_file"
}

# Display directory list for selection
display_directory_list() {
    local temp_dirs="$TEMP_PREFIX.dirs"
    local cursor_pos="${1:-0}"

    if [[ ! -f "$temp_dirs" ]] || [[ ! -s "$temp_dirs" ]]; then
        return 1
    fi

    local idx=0
    local max_size=0
    local total_size=0

    # Calculate totals
    max_size=$(head -1 "$temp_dirs" | cut -d'|' -f1)
    [[ -z "$max_size" ]] && max_size=1
    while IFS='|' read -r size path; do
        ((total_size += size))
    done < "$temp_dirs"
    [[ $total_size -eq 0 ]] && total_size=1

    # Display with cursor
    while IFS='|' read -r size path; do
        local human_size=$(bytes_to_human "$size")
        local percentage=$(calc_percentage "$size" "$total_size")
        local bar=$(generate_bar "$size" "$max_size" 20)
        local display_path=$(echo "$path" | sed "s|^$HOME|~|")
        local dirname=$(basename "$path")

        # Highlight selected line
        if [[ $idx -eq $cursor_pos ]]; then
            printf "  ${BLUE}▶${NC} %s [${GREEN}%s${NC}] %5s%%  %s\n" \
                "$bar" "$human_size" "$percentage" "$dirname"
        else
            printf "    %s [${BLUE}%s${NC}] %5s%%  %s\n" \
                "$bar" "$human_size" "$percentage" "$dirname"
        fi

        ((idx++))
        if [[ $idx -ge 15 ]]; then
            break
        fi
    done < "$temp_dirs"

    return 0
}

# Get path at cursor position
get_path_at_cursor() {
    local cursor_pos="$1"
    local temp_dirs="$TEMP_PREFIX.dirs"

    if [[ ! -f "$temp_dirs" ]]; then
        return 1
    fi

    local idx=0
    while IFS='|' read -r size path; do
        if [[ $idx -eq $cursor_pos ]]; then
            echo "$path"
            return 0
        fi
        ((idx++))
    done < "$temp_dirs"

    return 1
}

# Count available directories
count_directories() {
    local temp_dirs="$TEMP_PREFIX.dirs"
    if [[ ! -f "$temp_dirs" ]]; then
        echo "0"
        return
    fi
    local count=$(wc -l < "$temp_dirs" | tr -d ' ')
    [[ $count -gt 15 ]] && count=15
    echo "$count"
}

# Display interactive menu
display_interactive_menu() {
    clear_screen

    log_header "🔍 Disk Space Analyzer"
    echo ""
    echo "📂 Current: ${BLUE}$(echo "$CURRENT_PATH" | sed "s|^$HOME|~|")${NC}"
    echo ""

    # Show navigation hints
    echo "${GRAY}↑↓ Navigate | → Drill Down | ← Go Back | f Files | t Types | q Quit${NC}"
    echo ""

    # Display results based on view mode
    case "$VIEW_MODE" in
        "navigate")
            log_header "📁 Select Directory"
            echo ""
            display_directory_list "$CURSOR_POS"
            ;;
        "files")
            display_large_files
            ;;
        "types")
            display_file_types
            ;;
        *)
            display_large_files
            display_directories
            display_hotspots
            display_cleanup_suggestions
            ;;
    esac
}

# Analyze file types
display_file_types() {
    local temp_types="$TEMP_PREFIX.types"

    log_header "📊 File Types Analysis"
    echo ""

    if ! command -v mdfind &>/dev/null; then
        echo "  ${YELLOW}Note: mdfind not available, limited analysis${NC}"
        return
    fi

    # Analyze common file types
    local -A type_map=(
        ["Videos"]="kMDItemContentType == 'public.movie' || kMDItemContentType == 'public.video'"
        ["Images"]="kMDItemContentType == 'public.image'"
        ["Archives"]="kMDItemContentType == 'public.archive' || kMDItemContentType == 'public.zip-archive'"
        ["Documents"]="kMDItemContentType == 'com.adobe.pdf' || kMDItemContentType == 'public.text'"
        ["Audio"]="kMDItemContentType == 'public.audio'"
    )

    for type_name in "${!type_map[@]}"; do
        local query="${type_map[$type_name]}"
        local files=$(mdfind -onlyin "$CURRENT_PATH" "$query" 2>/dev/null)
        local count=$(echo "$files" | grep -c . || echo "0")
        local total_size=0

        if [[ $count -gt 0 ]]; then
            while IFS= read -r file; do
                if [[ -f "$file" ]]; then
                    local fsize=$(stat -f%z "$file" 2>/dev/null || echo "0")
                    ((total_size += fsize))
                fi
            done <<< "$files"

            if [[ $total_size -gt 0 ]]; then
                local human_size=$(bytes_to_human "$total_size")
                printf "  📦 %-12s %8s (%d files)\n" "$type_name:" "$human_size" "$count"
            fi
        fi
    done
    echo ""
}

# Read a single key press
read_single_key() {
    local key=""
    # Read single character without waiting for Enter
    if read -rsn1 key 2>/dev/null; then
        echo "$key"
    else
        echo "q"
    fi
}

# Fast scan with progress display
scan_directory_contents_fast() {
    local dir_path="$1"
    local output_file="$2"
    local max_items="${3:-16}"
    local show_progress="${4:-true}"

    local temp_all="$output_file.all"

    # Count items first for progress bar
    local total_dirs=$(find "$dir_path" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')

    local count=0
    local last_update=0

    # Get directories and files with sizes in parallel (much faster!)
    local temp_dirs="$output_file.dirs"
    local temp_files="$output_file.files"

    # Parallel directory scanning using xargs (4 parallel jobs)
    if [[ $total_dirs -gt 0 ]]; then
        # Start parallel scan
        find "$dir_path" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null | \
            xargs -0 -n 1 -P 4 sh -c '
                size=$(du -sk "$1" 2>/dev/null | cut -f1 || echo 0)
                echo "$((size * 1024))|dir|$1"
            ' _ > "$temp_dirs" &
        local du_pid=$!

        # Show progress while waiting
        if [[ "$show_progress" == "true" ]] && [[ $total_dirs -gt 10 ]]; then
            printf "\033[H\033[J" >&2
            echo "" >&2

            local spinner=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
            local i=0
            while kill -0 "$du_pid" 2>/dev/null; do
                # Count how many results we have so far
                local completed=$(wc -l < "$temp_dirs" 2>/dev/null | tr -d ' ')
                [[ -z "$completed" ]] && completed=0

                printf "\r  ${BLUE}📊 ${spinner[$((i % 10))]} Scanning: %d/%d completed${NC}" "$completed" "$total_dirs" >&2
                ((i++))
                sleep 0.15
            done
            printf "\r\033[K" >&2
        fi
        wait "$du_pid"
    else
        : > "$temp_dirs"
    fi

    # Files: get actual size (fast, no need for parallel)
    find "$dir_path" -mindepth 1 -maxdepth 1 -type f 2>/dev/null | while IFS= read -r item; do
        local size=$(stat -f%z "$item" 2>/dev/null || echo "0")
        echo "$size|file|$item"
    done > "$temp_files"

    # Combine and sort
    cat "$temp_dirs" "$temp_files" 2>/dev/null | sort -t'|' -k1 -rn | head -"$max_items" > "$output_file"

    # Cleanup
    rm -f "$temp_dirs" "$temp_files" 2>/dev/null

    # Clear progress line if shown
    if [[ "$show_progress" == "true" ]] && [[ $total_dirs -gt 10 ]]; then
        printf "\r\033[K" >&2
    fi
}

# Calculate directory sizes and update (now only used for deep refresh)
calculate_dir_sizes() {
    local items_file="$1"
    local max_items="${2:-15}"  # Only recalculate first 15 by default
    local temp_file="${items_file}.calc"

    # Since we now scan with actual sizes, this function is mainly for refresh
    # Just re-sort the existing data
    sort -t'|' -k1 -rn "$items_file" > "$temp_file"

    # Only update if source file still exists (might have been deleted if user quit)
    if [[ -f "$items_file" ]]; then
        mv "$temp_file" "$items_file" 2>/dev/null || true
    else
        rm -f "$temp_file" 2>/dev/null || true
    fi
}

# Combine initial scan results (large files + directories) into one list
combine_initial_scan_results() {
    local output_file="$1"
    local temp_large="$TEMP_PREFIX.large"
    local temp_dirs="$TEMP_PREFIX.dirs"

    > "$output_file"

    # Add directories
    if [[ -f "$temp_dirs" ]]; then
        while IFS='|' read -r size path; do
            echo "$size|dir|$path"
        done < "$temp_dirs" >> "$output_file"
    fi

    # Add large files (only files in current directory, not subdirectories)
    if [[ -f "$temp_large" ]]; then
        while IFS='|' read -r size path; do
            # Only include if parent directory is the current scan path
            local parent=$(dirname "$path")
            if [[ "$parent" == "$CURRENT_PATH" ]]; then
                echo "$size|file|$path"
            fi
        done < "$temp_large" >> "$output_file"
    fi

    # Sort by size
    sort -t'|' -k1 -rn "$output_file" -o "$output_file"
}

# Show all volumes overview and let user select
show_volumes_overview() {
    local temp_volumes="$TEMP_PREFIX.volumes"

    # Collect all mounted volumes
    {
        # Root volume
        local root_size=$(df -k / 2>/dev/null | tail -1 | awk '{print $3}')
        echo "$((root_size * 1024))|/|Macintosh HD (Root)"

        # External volumes
        if [[ -d "/Volumes" ]]; then
            find /Volumes -mindepth 1 -maxdepth 1 -type d 2>/dev/null | while IFS= read -r vol; do
                local vol_size=$(df -k "$vol" 2>/dev/null | tail -1 | awk '{print $3}')
                local vol_name=$(basename "$vol")
                echo "$((vol_size * 1024))|$vol|$vol_name"
            done
        fi

        # Common user directories
        for dir in "$HOME" "$HOME/Downloads" "$HOME/Documents" "$HOME/Library"; do
            if [[ -d "$dir" ]]; then
                local dir_size=$(du -sk "$dir" 2>/dev/null | cut -f1)
                local dir_name=$(echo "$dir" | sed "s|^$HOME|~|")
                echo "$((dir_size * 1024))|$dir|$dir_name"
            fi
        done
    } | sort -t'|' -k1 -rn > "$temp_volumes"

    # Setup alternate screen
    tput smcup 2>/dev/null || true
    printf "\033[?25l"  # Hide cursor

    cleanup_volumes() {
        printf "\033[?25h"  # Show cursor
        tput rmcup 2>/dev/null || true
    }
    trap cleanup_volumes EXIT INT TERM

    local cursor=0
    local total_items=$(wc -l < "$temp_volumes" | tr -d ' ')

    while true; do
        # Drain burst input (trackpad scroll -> many arrows)
        type drain_pending_input >/dev/null 2>&1 && drain_pending_input
        # Build output buffer to reduce flicker
        local output=""
        output+="\033[H\033[J"
        output+=$'\n'
        output+="\033[0;35m▶ 💾 Disk Volumes & Locations\033[0m"$'\n'
        output+=$'\n'
        output+="  ${GRAY}Select a location to explore. ↑/↓: Navigate | → / Enter: Open | ← / q: Quit${NC}"$'\n'
        output+=$'\n'
        output+="  TYPE  SIZE        LOCATION"$'\n'
        output+="  ────────────────────────────────────────────────────────────────────────────────"$'\n'

        local idx=0
        while IFS='|' read -r size path display_name; do
            local human_size=$(bytes_to_human "$size")

            # Determine icon
            local icon="💾"
            local color="${NC}"
            if [[ "$path" == "/" ]]; then
                icon="💿"
                color="${BLUE}"
            elif [[ "$path" == /Volumes/* ]]; then
                icon="🔌"
                color="${YELLOW}"
            elif [[ "$path" == "$HOME" ]]; then
                icon="🏠"
                color="${GREEN}"
            elif [[ "$path" == *"/Library" ]]; then
                icon="📚"
                color="${GRAY}"
            else
                icon="📁"
            fi

            # Build line
            local line=""
            if [[ $idx -eq $cursor ]]; then
                line=$(printf "  ${GREEN}▶${NC} ${color}%-4s  %-10s  %s${NC}" "$icon" "$human_size" "$display_name")
            else
                line=$(printf "    ${color}%-4s  %-10s  %s${NC}" "$icon" "$human_size" "$display_name")
            fi
            output+="$line"$'\n'

            ((idx++))
        done < "$temp_volumes"

        output+=$'\n'

        # Output everything at once
        printf "%b" "$output" >&2

        # Read key (suppress any escape sequences that might leak)
        local key
        key=$(read_key 2>/dev/null || echo "OTHER")

        case "$key" in
            "UP")
                ((cursor > 0)) && ((cursor--))
                ;;
            "DOWN")
                ((cursor < total_items - 1)) && ((cursor++))
                ;;
            "ENTER"|"RIGHT")
                # Get selected path
                local selected_path=""
                idx=0
                while IFS='|' read -r size path display_name; do
                    if [[ $idx -eq $cursor ]]; then
                        selected_path="$path"
                        break
                    fi
                    ((idx++))
                done < "$temp_volumes"

                if [[ -n "$selected_path" ]] && [[ -d "$selected_path" ]]; then
                    cleanup_volumes
                    trap - EXIT INT TERM
                    interactive_drill_down "$selected_path" ""
                    return
                fi
                ;;
            "QUIT"|"q")
                break
                ;;
        esac
    done

    cleanup_volumes
    trap - EXIT INT TERM
}

# Interactive drill-down mode
interactive_drill_down() {
    local start_path="$1"
    local initial_items="${2:-}"  # Pre-scanned items for first level
    local current_path="$start_path"
    local path_stack=()
    local cursor=0
    local need_scan=true
    local wait_for_calc=false  # Don't wait on first load, let user press 'r'
    local temp_items="$TEMP_PREFIX.items"

    # Cache variables to avoid recalculation
    local -a items=()
    local has_calculating=false
    local total_items=0

    # Setup alternate screen and hide cursor
    tput smcup 2>/dev/null || true  # Enter alternate screen
    printf "\033[?25l"  # Hide cursor

    # Cleanup on exit
    cleanup_drill_down() {
        printf "\033[?25h"  # Show cursor
        tput rmcup 2>/dev/null || true  # Exit alternate screen
    }
    trap cleanup_drill_down EXIT INT TERM

    while true; do
        # Drain any burst input (e.g. trackpad scroll converted to many arrow keys)
        type drain_pending_input >/dev/null 2>&1 && drain_pending_input
        # Only scan if needed (directory changed or refresh requested)
        if [[ "$need_scan" == "true" ]]; then
            # Clear screen for scanning
            printf "\033[H\033[J" >&2

            # Fast scan: list items immediately (top 16 only)
            scan_directory_contents_fast "$current_path" "$temp_items" 16

            # Load items into array
            items=()
            if [[ -f "$temp_items" ]] && [[ -s "$temp_items" ]]; then
                while IFS='|' read -r size type path; do
                    items+=("$size|$type|$path")
                done < "$temp_items"
            fi
            total_items=${#items[@]}

            # No more calculating state
            has_calculating=false
            need_scan=false
            wait_for_calc=false

            # Check if empty
            if [[ $total_items -eq 0 ]]; then
                # Empty directory - go back
                printf "\033[H\033[J" >&2
                echo "" >&2
                echo "  ${YELLOW}Empty directory${NC}" >&2
                echo "" >&2
                echo "  ${GRAY}Press any key to go back...${NC}" >&2
                read_key >/dev/null 2>&1
                if [[ ${#path_stack[@]} -gt 0 ]]; then
                    current_path="${path_stack[-1]}"
                    unset 'path_stack[-1]'
                    cursor=0
                    need_scan=true
                    continue
                else
                    break
                fi
            fi
        fi

        # Build output buffer once for smooth rendering
        local output=""
        output+="\033[H\033[J"  # Clear screen
        output+=$'\n'
        output+="\033[0;35m▶ 📊 Disk Space Explorer\033[0m"$'\n'
        output+=$'\n'
        output+="  ${BLUE}Current:${NC} $(echo "$current_path" | sed "s|^$HOME|~|")"$'\n'
        output+="  ${GRAY}↑/↓: Navigate | → / Enter: Open folder | ← / Backspace / q: Back | q: Quit${NC}"$'\n'
        output+=$'\n'
        output+="  ${YELLOW}Items (sorted by size):${NC}"$'\n'
        output+=$'\n'
        output+="  TYPE  SIZE        NAME"$'\n'
        output+="  ────────────────────────────────────────────────────────────────────────────────"$'\n'

        local max_show=16
        local idx=0
        for item_info in "${items[@]}"; do
            [[ $idx -ge $max_show ]] && break

            local size="${item_info%%|*}"
            local rest="${item_info#*|}"
            local type="${rest%%|*}"
            local path="${rest#*|}"
            local name=$(basename "$path")

            local human_size
            if [[ "$size" -eq 0 ]]; then
                human_size="0B"
            else
                human_size=$(bytes_to_human "$size")
            fi

            # Get icon and color
            local icon="" color="${NC}"
            if [[ "$type" == "dir" ]]; then
                icon="📁" color="${BLUE}"
                if [[ $size -gt 10737418240 ]]; then color="${RED}"
                elif [[ $size -gt 1073741824 ]]; then color="${YELLOW}"
                fi
            else
                local ext="${name##*.}"
                case "$ext" in
                    dmg|iso|pkg) icon="📦" ; color="${RED}" ;;
                    mov|mp4|avi|mkv|webm) icon="🎬" ; color="${YELLOW}" ;;
                    zip|tar|gz|rar|7z) icon="🗜️" ; color="${YELLOW}" ;;
                    pdf) icon="📄" ;;
                    jpg|jpeg|png|gif|heic) icon="🖼️" ;;
                    key|ppt|pptx) icon="📊" ;;
                    log) icon="📝" ; color="${GRAY}" ;;
                    *) icon="📄" ;;
                esac
            fi

            # Truncate name
            if [[ ${#name} -gt 55 ]]; then name="${name:0:52}..."; fi

            # Build line
            local line
            if [[ $idx -eq $cursor ]]; then
                line=$(printf "  ${GREEN}▶${NC} ${color}%-4s  %-10s  %s${NC}" "$icon" "$human_size" "$name")
            else
                line=$(printf "    ${color}%-4s  %-10s  %s${NC}" "$icon" "$human_size" "$name")
            fi
            output+="$line"$'\n'

            ((idx++))
        done

        output+=$'\n'

        # Output everything at once (single write = no flicker)
        printf "%b" "$output" >&2

        # Read key (suppress any escape sequences that might leak)
        local key
        key=$(read_key 2>/dev/null || echo "OTHER")

        case "$key" in
            "UP")
                ((cursor > 0)) && ((cursor--))
                ;;
            "DOWN")
                local max_cursor=$(( total_items < max_show ? total_items - 1 : max_show - 1 ))
                ((cursor < max_cursor)) && ((cursor++))
                ;;
            "ENTER"|"RIGHT")
                # Enter selected item (only if it's a directory)
                if [[ $cursor -lt ${#items[@]} ]]; then
                    local selected="${items[$cursor]}"
                    local size="${selected%%|*}"
                    local rest="${selected#*|}"
                    local type="${rest%%|*}"
                    local selected_path="${rest#*|}"

                    if [[ "$type" == "dir" ]]; then
                        path_stack+=("$current_path")
                        current_path="$selected_path"
                        cursor=0
                        need_scan=true
                    fi
                fi
                ;;
            "BACKSPACE"|"LEFT")
                # Go back
                if [[ ${#path_stack[@]} -gt 0 ]]; then
                    current_path="${path_stack[-1]}"
                    unset 'path_stack[-1]'
                    cursor=0
                    need_scan=true
                else
                    break
                fi
                ;;
            "QUIT"|"q")
                break
                ;;
            "r"|"R"|"SPACE")
                # Refresh: re-scan current directory
                need_scan=true
                wait_for_calc=true
                ;;
        esac
    done

    # Cleanup is handled by trap
}

# Main interactive loop
interactive_mode() {
    CURSOR_POS=0
    VIEW_MODE="overview"

    while true; do
        type drain_pending_input >/dev/null 2>&1 && drain_pending_input
        display_interactive_menu

        local key=$(read_key)
        case "$key" in
            "QUIT")
                break
                ;;
            "UP")
                if [[ "$VIEW_MODE" == "navigate" ]]; then
                    ((CURSOR_POS > 0)) && ((CURSOR_POS--))
                fi
                ;;
            "DOWN")
                if [[ "$VIEW_MODE" == "navigate" ]]; then
                    local max_count=$(count_directories)
                    ((CURSOR_POS < max_count - 1)) && ((CURSOR_POS++))
                fi
                ;;
            "RIGHT")
                if [[ "$VIEW_MODE" == "navigate" ]]; then
                    # Enter selected directory
                    local selected_path=$(get_path_at_cursor "$CURSOR_POS")
                    if [[ -n "$selected_path" ]] && [[ -d "$selected_path" ]]; then
                        CURRENT_PATH="$selected_path"
                        CURSOR_POS=0
                        perform_scan "$CURRENT_PATH"
                    fi
                else
                    # Enter navigation mode
                    VIEW_MODE="navigate"
                    CURSOR_POS=0
                fi
                ;;
            "LEFT")
                if [[ "$VIEW_MODE" == "navigate" ]]; then
                    # Go back to parent
                    if [[ "$CURRENT_PATH" != "$HOME" ]] && [[ "$CURRENT_PATH" != "/" ]]; then
                        CURRENT_PATH="$(dirname "$CURRENT_PATH")"
                        CURSOR_POS=0
                        perform_scan "$CURRENT_PATH"
                    fi
                else
                    VIEW_MODE="overview"
                fi
                ;;
            "f"|"F")
                VIEW_MODE="files"
                ;;
            "t"|"T")
                VIEW_MODE="types"
                ;;
            "ENTER")
                if [[ "$VIEW_MODE" == "navigate" ]]; then
                    # Same as RIGHT
                    local selected_path=$(get_path_at_cursor "$CURSOR_POS")
                    if [[ -n "$selected_path" ]] && [[ -d "$selected_path" ]]; then
                        CURRENT_PATH="$selected_path"
                        CURSOR_POS=0
                        perform_scan "$CURRENT_PATH"
                    fi
                else
                    break
                fi
                ;;
            *)
                # Any other key in overview mode exits
                if [[ "$VIEW_MODE" == "overview" ]]; then
                    break
                fi
                ;;
        esac
    done
}

# ============================================================================
# Main Entry Point
# ============================================================================

# Export results to CSV
export_to_csv() {
    local output_file="$1"
    local temp_dirs="$TEMP_PREFIX.dirs"

    if [[ ! -f "$temp_dirs" ]]; then
        log_error "No scan data available to export"
        return 1
    fi

    {
        echo "Size (Bytes),Size (Human),Path"
        while IFS='|' read -r size path; do
            local human=$(bytes_to_human "$size")
            echo "$size,\"$human\",\"$path\""
        done < "$temp_dirs"
    } > "$output_file"

    log_success "Exported to $output_file"
}

# Export results to JSON
export_to_json() {
    local output_file="$1"
    local temp_dirs="$TEMP_PREFIX.dirs"
    local temp_large="$TEMP_PREFIX.large"

    if [[ ! -f "$temp_dirs" ]]; then
        log_error "No scan data available to export"
        return 1
    fi

    {
        echo "{"
        echo "  \"scan_date\": \"$(date -u +"%Y-%m-%dT%H:%M:%SZ")\","
        echo "  \"target_path\": \"$CURRENT_PATH\","
        echo "  \"directories\": ["

        local first=true
        while IFS='|' read -r size path; do
            [[ "$first" == "false" ]] && echo ","
            first=false
            local human=$(bytes_to_human "$size")
            printf '    {"size": %d, "size_human": "%s", "path": "%s"}' "$size" "$human" "$path"
        done < "$temp_dirs"

        echo ""
        echo "  ],"
        echo "  \"large_files\": ["

        if [[ -f "$temp_large" ]]; then
            first=true
            while IFS='|' read -r size path; do
                [[ "$first" == "false" ]] && echo ","
                first=false
                local human=$(bytes_to_human "$size")
                printf '    {"size": %d, "size_human": "%s", "path": "%s"}' "$size" "$human" "$path"
            done < "$temp_large"
            echo ""
        fi

        echo "  ]"
        echo "}"
    } > "$output_file"

    log_success "Exported to $output_file"
}

main() {
    local target_path="$HOME"
    local interactive=false
    local export_format=""
    local export_file=""
    local show_volumes=false

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -i|--interactive)
                interactive=true
                shift
                ;;
            -a|--all)
                show_volumes=true
                shift
                ;;
            -e|--export)
                export_format="$2"
                export_file="${3:-disk_analysis_$(date +%Y%m%d_%H%M%S).$export_format}"
                shift 2
                [[ $# -gt 0 ]] && shift
                ;;
            -h|--help)
                echo "Usage: mole analyze [options] [path]"
                echo ""
                echo "Interactive disk space explorer - navigate like a file manager, sorted by size."
                echo ""
                echo "Options:"
                echo "  -a, --all         Start with all volumes view (/, /Volumes/*)"
                echo "  -i, --interactive Use old interactive mode (legacy)"
                echo "  -h, --help        Show this help"
                echo ""
                echo "Examples:"
                echo "  mole analyze              # Explore home directory"
                echo "  mole analyze --all        # Start with all disk volumes"
                echo "  mole analyze ~/Downloads  # Explore Downloads"
                echo "  mole analyze ~/Library    # Check system caches"
                echo ""
                echo "Features:"
                echo "  • Files and folders mixed together, sorted by size (largest first)"
                echo "  • Shows top 16 items per directory (largest items only)"
                echo "  • Use ↑/↓ to navigate, Enter to open folders, Backspace to go back"
                echo "  • Files (📦🎬📄) shown but can't be opened, only folders (📁) can"
                echo "  • Color coding: Red folders >10GB, Yellow >1GB, installers/videos highlighted"
                echo "  • Press q to quit at any time"
                exit 0
                ;;
            -*)
                log_error "Unknown option: $1"
                exit 1
                ;;
            *)
                target_path="$1"
                shift
                ;;
        esac
    done

    # Validate path
    if [[ ! -d "$target_path" ]]; then
        log_error "Invalid path: $target_path"
        exit 1
    fi

    CURRENT_PATH="$target_path"

    # Create cache directory
    mkdir -p "$CACHE_DIR" 2>/dev/null || true

    # Handle export if requested (requires scan)
    if [[ -n "$export_format" ]]; then
        # Check for mdfind
        if ! command -v mdfind &>/dev/null; then
            log_warning "mdfind not available, falling back to slower scan method"
        fi

        perform_scan "$target_path"

        case "$export_format" in
            csv)
                export_to_csv "$export_file"
                exit 0
                ;;
            json)
                export_to_json "$export_file"
                exit 0
                ;;
            *)
                log_error "Unknown export format: $export_format (use csv or json)"
                exit 1
                ;;
        esac
    fi

    if [[ "$interactive" == "true" ]]; then
        # Old interactive mode (keep for compatibility)
        if ! command -v mdfind &>/dev/null; then
            log_warning "mdfind not available, falling back to slower scan method"
        fi
        perform_scan "$target_path"
        interactive_mode
    else
        # Show volumes view if requested
        if [[ "$show_volumes" == "true" ]]; then
            show_volumes_overview
        else
            # New default: directly enter interactive drill-down mode (NO initial scan!)
            interactive_drill_down "$target_path" ""
        fi
    fi
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi