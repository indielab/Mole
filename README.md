<div align="center">
  <img src="https://cdn.tw93.fun/pic/cole.png" alt="Mole Logo" width="120" height="120" style="border-radius:50%" />
  <h1 style="margin: 12px 0 6px;">Mole</h1>
  <p><em>🦡 Dig deep like a mole to clean your Mac.</em></p>
</div>

## Highlights

- 🐦 **Deep System Cleanup** - Remove hidden caches, logs, and temp files in one sweep
- 📦 **Smart Uninstall** - Complete app removal with all related files and folders
- ⚡️ **Fast Interactive UI** - Arrow-key navigation with pagination for large lists
- 🧹 **Massive Space Recovery** - Reclaim 100GB+ of wasted disk space

## Installation

```bash
curl -fsSL https://raw.githubusercontent.com/tw93/mole/main/install.sh | bash
```

> 📖 **不会用终端？** 查看 [小白使用指南](./GUIDE.md) 了解详细的教程

## Usage

```bash
mole                      # Interactive main menu
mole clean                # Deep system cleanup
mole clean --dry-run      # Preview cleanup (no deletions)
mole uninstall            # Interactive app uninstaller
mole update               # Update Mole to the latest version
mole --help               # Show help
```

**Navigation:** Use arrow keys (↑/↓), Space to select, Enter to confirm, Q to quit or Ctrl+C to force exit.

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

## What Mole Cleans

| Category | Targets | Typical Recovery |
|----------|---------|------------------|
| **System** | App caches, logs, trash, crash reports | 20-50GB |
| **Browsers** | Safari, Chrome, Edge, Arc, Firefox cache | 5-15GB |
| **Developer** | npm, pip, Docker, Homebrew, Xcode | 15-40GB |
| **Apps** | Slack, Discord, Teams, Notion cache | 3-10GB |

**Protect Important Files:** Create `~/.config/mole/whitelist` to preserve critical caches:

```bash
# View current whitelist
mole clean --whitelist

# Example: Protect Playwright browsers and build tools
echo '~/Library/Caches/ms-playwright*' >> ~/.config/mole/whitelist
```

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

- If Mole helps you recover disk space, star this repository and share with fellow Mac users.
- Report issues via [GitHub Issues](https://github.com/tw93/mole/issues).
- I have two cats, you can <a href="https://miaoyan.app/cats.html?name=Mole" target="_blank">feed them canned food</a> if you'd like.

## License

MIT License - feel free to enjoy and participate in open source.
