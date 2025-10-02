<div align="center">
  <img src="https://cdn.tw93.fun/pic/cole.png" alt="Mole Logo" width="120" height="120" style="border-radius:50%" />
  <h1 style="margin: 12px 0 6px;">Mole</h1>
  <p><em>🦡 Dig deep like a mole to clean your Mac.</em></p>
</div>

## Highlights

- 🦡 **Deep System Cleanup** - Remove hidden caches, logs, and temp files in one sweep
- 📦 **Smart Uninstall** - Complete app removal with all related files and folders
- 📊 **Disk Space Analyzer** - Visualize disk usage with lightning-fast mdfind + du hybrid scanning
- ⚡️ **Fast Interactive UI** - Arrow-key navigation with pagination for large lists
- 🧹 **Massive Space Recovery** - Reclaim 100GB+ of wasted disk space

## Installation

```bash
curl -fsSL https://raw.githubusercontent.com/tw93/mole/main/install.sh | bash
```

## Usage

```bash
mole               # Interactive main menu
mole clean         # Deep system cleanup
mole uninstall     # Interactive app uninstaller
mole analyze [path]# Analyze disk space (default: home directory)
mole --help        # Show help
```

## Examples

### Deep System Cleanup

```bash
$ mole clean

Starting user-level cleanup...

▶ System essentials
  ✓ User app cache (28 items) (45.2GB)
  ✓ User app logs (15 items) (2.1GB)
  ✓ Trash (12.3GB)

▶ Browser cleanup
  ✓ Chrome cache (8 items) (8.4GB)
  ✓ Safari cache (2.1GB)
  ✓ Arc cache (3.2GB)

▶ Extended developer caches
  ✓ Xcode derived data (9.1GB)
  ✓ Node.js cache (4 items) (14.2GB)
  ✓ VS Code cache (1.4GB)

▶ Applications
  ✓ JetBrains cache (3.8GB)
  ✓ Slack cache (2.2GB)
  ✓ Discord cache (1.8GB)

====================================================================
🎉 CLEANUP COMPLETE!
💾 Space freed: 95.50GB | Free space now: 223.5GB
📊 Files cleaned: 6420 | Categories processed: 6
====================================================================
```

### Smart App Uninstaller

```bash
$ mole uninstall

Select Apps to Remove

▶ ☑ Adobe Creative Cloud      (12.4G) | Old
  ☐ WeChat                    (2.1G) | Recent
  ☐ Final Cut Pro             (3.8G) | Recent

🗑️  Uninstalling: Adobe Creative Cloud
  ✓ Removed application
  ✓ Cleaned 45 related files

====================================================================
🎉 UNINSTALLATION COMPLETE!
🗑️ Apps uninstalled: 1 | Space freed: 12.4GB
====================================================================
```

### Disk Space Analyzer

```bash
# Quick start - explore your home directory
$ mole analyze

# View all disk volumes and major locations
$ mole analyze --all

💾 Disk Volumes & Locations

  TYPE  SIZE        LOCATION
  ────────────────────────────────────────────────────────────────────────────────
▶ 💿  245.3GB     Macintosh HD (Root)
  🏠  89.2GB      ~
  📚  45.1GB      ~/Library
  📁  33.7GB      ~/Downloads
  📁  18.4GB      ~/Documents
  🔌  128.0GB     External Drive

# Explore specific directory with progress bar
$ mole analyze ~/Downloads

  📊 [████████████] 100% (25/25)  ← Real-time scanning progress

📊 Disk Space Explorer

  Current: ~/Downloads
  ↑/↓: Navigate | → / Enter: Open folder | ← / Backspace: Back | q: Quit

  Items (sorted by size):

  TYPE  SIZE        NAME
  ────────────────────────────────────────────────────────────────────────────────
  ▶ 📁   33.72GB      materials       ← Use arrow keys to select
    📁   5.67GB       learning
    📁   4.50GB       projects
    🎬   1.68GB       recording.mov   ← Files can't be opened
    🎬   1.58GB       presentation.mov
    📦   1.20GB       OldInstaller.dmg
    📁   2.22GB       shared
    📁   1.78GB       recent
    ... and 12 more items

# Press Enter on "materials" folder to drill down:

📊 Disk Space Explorer

  Current: ~/Downloads/materials
  ↑/↓: Navigate | → / Enter: Open folder | ← / Backspace: Back | q: Quit

  Items (sorted by size):

  ▶ 📁   15.2GB       videos          ← Keep drilling down
    📁   10.1GB       documents
    📁   6.8GB        images
    🎬   2.5GB        demo.mov
```

**Interactive Navigation:**

- **Instant startup** - no waiting for initial scan
- **Real-time progress** - visual progress bar when scanning (10+ directories)
- **All volumes view** - `--all` flag shows all disks and major locations
- **Files and folders mixed together**, sorted by size (largest first)
- Shows **top 16 items** per directory (largest items only)
- Use **↑/↓** arrow keys to navigate (green arrow ▶ shows selection)
- Press **Enter** on a 📁 folder to drill down into it
- Press **Backspace** or **←** to go back to parent directory
- Press **q** to quit at any time
- **Color coding**: Red folders >10GB, Yellow >1GB, Blue <1GB
- Files (📦🎬📄🖼️📊) are shown but can't be opened (only folders)

**Performance:**
- **Fast scanning** - real-time progress bar for large directories (10+ folders)
- **Smart caching** - sizes are calculated once and cached during navigation
- **Top 16 only** - shows largest items first, keeps interface clean and fast

## What Mole Cleans

| Category | Targets | Typical Recovery |
|----------|---------|------------------|
| **System** | App caches, logs, trash, crash reports | 20-50GB |
| **Browsers** | Safari, Chrome, Edge, Arc, Firefox cache | 5-15GB |
| **Developer** | npm, pip, Docker, Homebrew, Xcode | 15-40GB |
| **Apps** | Slack, Discord, Teams, Notion cache | 3-10GB |

## What Mole Uninstalls

| Component | Files Removed | Examples |
|-----------|--------------|----------|
| **App Bundle** | Main .app executable | `/Applications/App.app` |
| **Support Data** | App-specific user data | `~/Library/Application Support/AppName` |
| **Cache Files** | Temporary & cache data | `~/Library/Caches/com.company.app` |
| **Preferences** | Settings & config files | `~/Library/Preferences/com.app.plist` |
| **Logs & Reports** | Crash reports & logs | `~/Library/Logs/AppName` |
| **Containers** | Sandboxed app data | `~/Library/Containers/com.app.id` |

## Support

If Mole helps you recover disk space, star this repository and share with fellow Mac users. Report issues via [GitHub Issues](https://github.com/tw93/mole/issues).

I have two cats, you can <a href="https://miaoyan.app/cats.html?name=Mole" target="_blank">feed them canned food</a> if you'd like.

## License

MIT License - feel free to enjoy and participate in open source.
