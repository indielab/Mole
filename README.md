<div align="center">
  <h1>Mole</h1>
  <p><em>🐹 Dig deep like a mole to clean your Mac.</em></p>
</div>

<p align="center">
  <a href="https://github.com/tw93/mole/stargazers"><img src="https://img.shields.io/github/stars/tw93/mole?style=flat-square" alt="Stars"></a>
  <a href="https://github.com/tw93/mole/releases"><img src="https://img.shields.io/github/v/tag/tw93/mole?label=version&style=flat-square" alt="Version"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue.svg?style=flat-square" alt="License"></a>
  <a href="https://github.com/tw93/mole/commits"><img src="https://img.shields.io/github/commit-activity/m/tw93/mole?style=flat-square" alt="Commits"></a>
  <a href="https://twitter.com/HiTw93"><img src="https://img.shields.io/badge/follow-Tw93-red?style=flat-square&logo=Twitter" alt="Twitter"></a>
  <a href="https://t.me/+GclQS9ZnxyI2ODQ1"><img src="https://img.shields.io/badge/chat-Telegram-blueviolet?style=flat-square&logo=Telegram" alt="Telegram"></a>
</p>

<p align="center">
  <img src="https://cdn.tw93.fun/img/mole.jpeg" alt="Mole - 95.50GB freed" width="800" />
</p>

## Features

- 🐦 **Deep System Cleanup** - Remove hidden caches, logs, and temp files in one sweep
- 📦 **Thorough Uninstall** - 22+ locations cleaned vs 1 standard, beats CleanMyMac/Lemon
- 📊 **Interactive Disk Analyzer** - Navigate folders like a file manager, find and delete large files instantly
- ⚡️ **Fast & Lightweight** - Terminal-based, zero bloat, arrow-key navigation with pagination

## Quick Start

**Tips:**

- On mission-critical Macs, wait for Mole to mature, safety first
- 如果这台 Mac 对你非常重要，建议等 Mole 更成熟时来使用，安全第一
- I'm not very tech-savvy？Check [小白使用指南](./GUIDE.md)

**Install:**

```bash
curl -fsSL https://raw.githubusercontent.com/tw93/mole/main/install.sh | bash
```

Or via Homebrew:

```bash
brew install tw93/tap/mole
```

**Run:**

```bash
mo                      # Interactive menu
mo clean                # System cleanup
mo clean --dry-run      # Preview mode
mo clean --whitelist    # Manage protected caches
mo uninstall            # Uninstall apps
mo analyze              # Disk analyzer
mo update               # Update Mole
mo remove               # Remove Mole from system
mo --help               # Show help
mo --version            # Show installed version
# If the command is not found, run `mole update` once to upgrade to the latest version.
```

> Recommended start with `mo clean --dry-run` to preview, `mo clean --whitelist` to protect caches

## Features in Detail

### Deep System Cleanup

```bash
$ mo clean

▶ System essentials
  ✓ User app cache (45.2GB)
  ✓ User app logs (2.1GB)
  ✓ Trash (12.3GB)

▶ Browser cleanup
  ✓ Chrome cache (8.4GB)
  ✓ Safari cache (2.1GB)

▶ Developer tools
  ✓ Xcode derived data (9.1GB)
  ✓ Node.js cache (14.2GB)

▶ Others
  ✓ Dropbox cache (5.2GB)
  ✓ Spotify cache (3.1GB)

====================================================================
🎉 CLEANUP COMPLETE!
💾 Space freed: 95.50GB | Free space now: 223.5GB
====================================================================
```

### Smart App Uninstaller

```bash
$ mo uninstall

🗑️  Select Apps to Remove
═══════════════════════════
▶ ☑ Adobe Creative Cloud      (12.4G) | Old
  ☐ WeChat                    (2.1G) | Recent
  ☐ Final Cut Pro             (3.8G) | Recent

🗑️  Uninstalling: Adobe Creative Cloud
  ✓ Removed application              # /Applications/
  ✓ Cleaned 52 related files         # ~/Library/ across 12 locations
    - Support files & caches         # Application Support, Caches
    - Preferences & logs             # Preferences, Logs
    - WebKit storage & cookies       # WebKit, HTTPStorages
    - Extensions & plugins           # Internet Plug-Ins, Services
    - System files with sudo         # /Library/, Launch daemons

====================================================================
🎉 UNINSTALLATION COMPLETE!
💾 Space freed: 12.8GB
====================================================================
```

### Disk Space Analyzer

```bash
$ mo analyze

📊 Analyzing: /Users/You
═══════════════════════════════════════════════════════
Total: 156.8GB

├─ 📁 Library                                        45.2GB
│  ├─ 📁 Caches                                      28.4GB
│  └─ 📁 Application Support                         16.8GB
├─ 📁 Downloads                                      32.6GB
│  ├─ 📄 Xcode-14.3.1.dmg                            12.3GB
│  ├─ 📄 backup_2023.zip                             8.6GB
│  └─ 📦 old_projects.tar.gz                         5.2GB
├─ 📁 Movies                                         28.9GB
│  ├─ 📄 vacation_2023.mov                           15.4GB
│  └─ 📄 screencast_raw.mp4                          8.8GB
├─ 📁 Documents                                      18.4GB
└─ 📁 Desktop                                        12.7GB
```

## FAQ

1. **Is Mole safe?** – Mole focuses on cleaning caches and logs, without touching app settings, user documents, or system files. You can run `mo clean --dry-run` to preview what will be removed before actually cleaning.  
2. **How often should I clean?** – About once a month, or whenever you notice disk space running low.  
3. **Can I protect specific caches?** – Yes. Run `mo clean --whitelist` to interactively choose which caches to keep. Some common ones like Playwright browsers and HuggingFace models are already protected by default.  

## Support

- **Star this repo** if Mole helped you recover disk space
- **Share with friends** who need to clean their Macs
- **Report issues** via [GitHub Issues](https://github.com/tw93/mole/issues)
- I have two cats, <a href="https://miaoyan.app/cats.html?name=Mole" target="_blank">feed them canned food</a> if you'd like

## License

MIT License - feel free to enjoy and participate in open source.
