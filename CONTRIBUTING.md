# Contributing to Mole

## Setup

```bash
# Install tools
brew install shfmt shellcheck bats-core

# Install git hooks (optional)
./scripts/install-hooks.sh
```

## Development

```bash
# Format code
./scripts/format.sh

# Run tests
./tests/run.sh

# Check quality
shellcheck -S warning mole bin/*.sh lib/*.sh
```

## Git Hooks

Pre-commit hook will auto-format your code. Install with:
```bash
./scripts/install-hooks.sh
```

Skip if needed: `git commit --no-verify`

## Code Style

- Bash 3.2+ compatible
- 4 spaces indent
- Use `set -euo pipefail`
- Quote all variables
- BSD commands not GNU

Config: `.editorconfig` and `.shellcheckrc`

## Pull Requests

1. Fork and create branch
2. Make changes
3. Format: `./scripts/format.sh`
4. Test: `./tests/run.sh`
5. Commit and push
6. Open PR

CI will check formatting, lint, and run tests.
