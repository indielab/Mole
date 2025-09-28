<div align="center">
  <img src="https://cdn.tw93.fun/pic/cole.png" alt="Mole Logo" width="120" height="120" style="border-radius:50%" />
  <h1 style="margin: 12px 0 6px;">Mole</h1>
  <p><em>🦡 Dig deep like a mole to clean your Mac.</em></p>
</div>

## Highlights

- 🦡 Deep-clean hidden caches, logs, and temp files in one sweep
- 🛡 Guardrails built in: skip vital macOS and input method data
- 📦 Smart uninstall removes apps together with every leftover directory
- ⚡️ Fast arrow-key TUI with pagination for big app lists

## Installation

```bash
curl -fsSL https://raw.githubusercontent.com/tw93/mole/main/install.sh | bash
```

## Usage

```bash
mole               # Interactive main menu
mole clean         # Deeper system cleanup
mole uninstall     # Interactive app uninstaller
mole --help        # Show help
```

### Quick Peek

```bash
$ mole clean
🕳️ Mole - Deeper system cleanup
==================================================

🍎 Detected: Apple Silicon M3 | 💾 Free space: 245GB

------------------------------ System essentials ------------------------------
  ✓ User app cache (20.8GB)
  ✓ User app logs (190MB)
  ✓ Trash (5.4GB)

------------------------------ Browser cleanup --------------------------------
  ✓ Safari cache (320MB)
  ✓ Chrome cache (1.2GB)
  ✓ Arc cache (460MB)

------------------------------ Developer tools --------------------------------
  ✓ npm cache cleaned
  ✓ Docker resources cleaned
  ✓ Homebrew cache (940MB)

------------------------------ Cleanup summary --------------------------------
🎉 Cleanup complete | 💾 Freed space: 38.6GB
📊 Items processed: 356 | 💾 Free space now: 253GB
===================================================================
```

## What Mole Cleans

| Category | Items Cleaned | Safety |
|---|---|---|
| 🗂️ System | App caches, logs, trash, crash reports, QuickLook thumbnails | Safe |
| 🌐 Browsers | Safari, Chrome, Edge, Arc, Brave, Firefox, Opera, Vivaldi | Safe |
| 💻 Developer | Node.js/npm, Python/pip, Go, Rust/cargo, Docker, Homebrew, Git | Safe |
| 🛠️ IDEs | Xcode, VS Code, JetBrains, Android Studio, Unity, Figma | Safe |
| 📱 Apps | Common app caches (e.g., Slack, Discord, Teams, Notion, 1Password) | Safe |
| 🍎 Apple Silicon | Rosetta 2, media services, user activity caches | Safe |

## Smart Uninstall

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
- I have two cats. If Mole helps you, you can <a href="https://miaoyan.app/cats.html?name=Mole" target="_blank">feed them canned food 🥩🍤</a>

## License

MIT License © [tw93](https://github.com/tw93) - Feel free to enjoy and contribute to open source.
