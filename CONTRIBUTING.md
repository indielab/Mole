# Contributing to Mole

## Setup

```bash
# Install development tools
brew install shfmt shellcheck bats-core
```

## Development

Run all quality checks before committing:

```bash
./scripts/check.sh
```

This command runs:

- Code formatting check
- ShellCheck linting
- Unit tests

Individual commands:

```bash
# Format code
./scripts/format.sh

# Run tests only
./tests/run.sh
```

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
3. Run checks: `./scripts/check.sh`
4. Commit and push
5. Open PR

CI will verify formatting, linting, and tests.
