<div align="center">
<img src="https://gw.alipayobjects.com/zos/k/gj/clean.svg" alt="Clean Mac" width="120" height="120"/>

# Clean Mac

**🧹 Deep Clean Your Mac with One Click**

[![GitHub release](https://img.shields.io/github/release/tw93/clean-mac.svg)](https://github.com/tw93/clean-mac/releases) [![Homebrew](https://img.shields.io/badge/Homebrew-available-green.svg)](https://formulae.brew.sh/formula/clean-mac) [![License](https://img.shields.io/github/license/tw93/clean-mac.svg)](https://github.com/tw93/clean-mac/blob/main/LICENSE) [![macOS](https://img.shields.io/badge/macOS-10.14+-blue.svg)](https://github.com/tw93/clean-mac)
</div>

## Features

- 🔥 **More Thorough** - Cleans significantly more cache than other tools
- ⚡ **Dead Simple** - Just one command, no complex setup or GUI
- 👀 **Transparent & Safe** - Open source code you can review and customize
- 🛡️ **Zero Risk** - Only touches safe cache files, never important data

## Installation

### Quick Install (Recommended)

```bash
curl -fsSL https://raw.githubusercontent.com/tw93/clean-mac/main/install.sh | bash
```

### Homebrew (Coming Soon)

```bash
# Will be available soon
brew install clean-mac
```

### Development

```bash
# Clone and run locally
git clone https://github.com/tw93/clean-mac.git
cd clean-mac && chmod +x clean.sh && ./clean.sh
```

## Usage

```bash
clean              # Daily cleanup (no password required)
clean --system     # Deep system cleanup (password required)
clean --help       # Show help information
```

### Example Output

```bash
🧹 Clean Mac - Deep Clean Your Mac with One Click
================================================
🍎 Detected: Apple Silicon (M-series) | 💾 Free space: 45.2GB
🚀 Mode: User-level cleanup (no password required)

▶ System essentials
  ✓ User app cache (1.2GB)
  ✓ User app logs (256MB)
  ✓ Trash (512MB)

▶ Browser cleanup
  ✓ Safari cache (845MB)
  ✓ Chrome cache (1.8GB)

▶ Developer tools
  ✓ npm cache cleaned
  ✓ Docker resources cleaned
  ✓ Homebrew cache (2.1GB)

🎉 User-level cleanup complete | 💾 Freed space: 8.45GB
📊 Items processed: 342 | 💾 Free space now: 53.7GB
```

## What Gets Cleaned

| Category | Items Cleaned | Safety Level |
|----------|---------------|--------------|
| **🗂️ System** | App caches, logs, trash, crash reports, QuickLook thumbnails | ✅ Safe |
| **🌐 Browsers** | Safari, Chrome, Edge, Arc, Brave, Firefox, Opera, Vivaldi | ✅ Safe |
| **💻 Developer** | Node.js, Python, Go, Rust, Docker, Homebrew, Git, Cloud CLI | ✅ Safe |
| **🛠️ IDEs** | Xcode, VS Code, JetBrains, Android Studio, Unity, Figma | ✅ Safe |
| **📱 Apps** | Discord, Slack, Teams, Notion, 1Password, Steam, Epic Games | ✅ Safe |
| **🍎 Apple Silicon** | Rosetta 2, M-series media cache, user activity cache | ✅ Safe |
| **🔒 System Deep** | Font caches, iCloud sync, Adobe, VMs, system logs | 🌚 --system flag |

## Support

If Clean Mac has been helpful to you:

- **Star this repository** and share with fellow Mac users
- **Report issues** or suggest new cleanup targets
- I have two cats, if you think Clean helps you, you can <a href="https://miaoyan.app/cats.html?name=CleanMac" target="_blank">feed them canned food 🥩🍤</a>

## License

MIT License © [tw93](https://github.com/tw93) - Feel free to enjoy and contribute to open source.
