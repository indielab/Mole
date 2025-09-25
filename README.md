<div align="center">
  <img src="https://cdn.tw93.fun/pic/cole.jpg" alt="Mole Logo" width="96" height="96" style="border-radius:50%" />
  <h1 style="margin: 12px 0 6px;">Mole</h1>
  <p><em>Like a mole, dig deep to clean your mac.</em></p>
</div>

## Features

- 🐦 Deep Clean: System/user caches, logs, temp and more
- 🛡️ Safe by default: Skips critical system and input method settings
- 👀 App Uninstall: Remove app bundle and related data comprehensively
- 👻 Smooth TUI: Fast arrow-key menus with pagination for large lists

## Installation

```bash
curl -fsSL https://raw.githubusercontent.com/tw93/clean-mac/main/install.sh | bash
```

## Usage

```bash
mole               # Interactive main menu
mole clean         # Deep clean (smart sudo handling)
mole uninstall     # Interactive app uninstaller
mole --help        # Show help
```

### Example Output

```bash
🕳️ Mole - System Cleanup
========================
🍎 Detected: Apple Silicon | 💾 Free space: 45.2GB
🚀 Mode: User-level cleanup (no password required)

▶ System essentials
  ✓ User app cache
  ✓ User app logs
  ✓ Trash

▶ Browser cleanup
  ✓ Safari cache
  ✓ Chrome cache

▶ Developer tools
  ✓ npm cache
  ✓ Docker resources
  ✓ Homebrew cache

🎉 Cleanup complete | 💾 Freed space: 8.45GB
📊 Items processed: 342 | 💾 Free space now: 53.7GB
```

## What Gets Cleaned

| Category | Items Cleaned | Safety |
|---|---|---|
| 🗂️ System | App caches, logs, trash, crash reports, QuickLook thumbnails | Safe |
| 🌐 Browsers | Safari, Chrome, Edge, Arc, Brave, Firefox, Opera, Vivaldi | Safe |
| 💻 Developer | Node.js/npm, Python/pip, Go, Rust/cargo, Docker, Homebrew, Git | Safe |
| 🛠️ IDEs | Xcode, VS Code, JetBrains, Android Studio, Unity, Figma | Safe |
| 📱 Apps | Common app caches (e.g., Slack, Discord, Teams, Notion, 1Password) | Safe |
| 🍎 Apple Silicon | Rosetta 2, media services, user activity caches | Safe |

## Uninstaller

- Fast scan of `/Applications` with system-app filtering (e.g., `com.apple.*`)
- Ranks apps by last used time and shows size hints
- Two modes: batch multi-select (checkbox) or quick single-select
- Detects running apps and force‑quits them before removal
- Single confirmation for the whole batch with estimated space to free
- Cleans thoroughly and safely:
  - App bundle (`.app`)
  - `~/Library/Application Support/<App|BundleID>`
  - `~/Library/Caches/<BundleID>`
  - `~/Library/Preferences/<BundleID>.plist`
  - `~/Library/Logs/<App|BundleID>`
  - `~/Library/Saved Application State/<BundleID>.savedState`
  - `~/Library/Containers/<BundleID>` and related Group Containers
- Final summary: apps removed, files cleaned, total disk space reclaimed

## Support

If Mole has been helpful to you:

- **Star this repository** and share with fellow Mac users
- **Report issues** or suggest new cleanup targets
- I have two cats, if you think Clean helps you, you can <a href="https://miaoyan.app/cats.html?name=CleanMac" target="_blank">feed them canned food 🥩🍤</a>

## License

MIT License © [tw93](https://github.com/tw93) - Feel free to enjoy and contribute to open source.
