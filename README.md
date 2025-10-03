<div align="center">
  <img src="https://cdn.tw93.fun/pic/cole.png" alt="Mole Logo" width="120" height="120" style="border-radius:50%" />
  <h1 style="margin: 12px 0 6px;">Mole</h1>
  <p><em>🦡 Dig deep like a mole to clean your Mac.</em></p>
</div>

<p align="center">
  <a href="https://github.com/tw93/mole/stargazers"><img src="https://img.shields.io/github/stars/tw93/mole?style=flat-square" alt="Stars"></a>
  <a href="https://github.com/tw93/mole/releases"><img src="https://img.shields.io/github/v/tag/tw93/mole?label=version&style=flat-square" alt="Version"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue.svg?style=flat-square" alt="License"></a>
  <a href="https://github.com/tw93/mole/commits"><img src="https://img.shields.io/github/commit-activity/m/tw93/mole?style=flat-square" alt="Commits"></a>
  <a href="https://twitter.com/HiTw93"><img src="https://img.shields.io/badge/follow-Tw93-red?style=flat-square&logo=Twitter" alt="Twitter"></a>
  <a href="https://t.me/+GclQS9ZnxyI2ODQ1"><img src="https://img.shields.io/badge/chat-Telegram-blueviolet?style=flat-square&logo=Telegram" alt="Telegram"></a>
</p>

## Highlights

- 🐦 **Deep System Cleanup** - Remove hidden caches, logs, and temp files in one sweep
- 📦 **Thorough Uninstall** - Removes more app leftovers than CleanMyMac/Lemon, completely free
- ⚡️ **Fast & Lightweight** - Terminal-based, zero bloat, arrow-key navigation with pagination
- 🧹 **Massive Space Recovery** - Reclaim 100GB+ of wasted disk space

## Installation

```bash
curl -fsSL https://raw.githubusercontent.com/tw93/mole/main/install.sh | bash
```

Or via Homebrew:

```bash
brew install tw93/tap/mole
```

> Pick one method to avoid conflicts, new users check [小白使用指南](./GUIDE.md)

## Usage

```bash
mole                      # Interactive main menu
mole clean                # Deep system cleanup
mole clean --dry-run      # Preview cleanup (no deletions)
mole uninstall            # Interactive app uninstaller
mole update               # Update to latest version
mole --help               # Show help
```

> Installed via Homebrew? Use `brew upgrade mole` to update

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

## FAQ

1. **Will Mole delete important files?** - No. Mole has built-in protection and skips system-critical files.
2. **Can I undo cleanup operations?** - Cache files are safe to delete and will regenerate automatically.
3. **How often should I run cleanup?** - Once a month is sufficient. Run when disk space is low.
4. **Is it safe to use?** - Yes. The tool previews what will be deleted before any action (`--dry-run`).

## Support

- ⭐️ **Star this repo** if Mole helped you recover disk space
- 🐛 **Report issues** via [GitHub Issues](https://github.com/tw93/mole/issues)
- 💬 **Share with friends** who need to clean their Macs
- 🐱 I have two cats, <a href="https://miaoyan.app/cats.html?name=Mole" target="_blank">feed them canned food</a> if you'd like

## License

MIT License - feel free to enjoy and participate in open source.
