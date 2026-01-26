# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This repository provides a hardened sandbox script (`csandbox.sh` v1.0.0) for running Claude Code in an isolated environment using bubblewrap (bwrap).

## Usage

```bash
./csandbox.sh [OPTIONS] [-- CLAUDE_ARGS...]
```

### Options

| Option | Description |
|--------|-------------|
| `-h, --help` | Show help message |
| `-v, --version` | Show version |
| `-p, --safe-mode` | Enable safe mode (prompt for permissions) |
| `-s, --include-sensitive` | Disable sensitive file protection (NOT RECOMMENDED) |
| `-l, --log` | Enable session logging to file |
| `-e, --protect-env` | Block .env files in working directory |

### Examples

```bash
./csandbox.sh                     # Default settings (skip permissions)
./csandbox.sh --safe-mode         # Prompt for permissions
./csandbox.sh --log               # Enable session logging
./csandbox.sh --protect-env       # Block .env files
./csandbox.sh -- --model opus     # Pass arguments to Claude
```

### Prerequisites

Install bubblewrap:
- Debian/Ubuntu: `sudo apt install bubblewrap`
- Fedora: `sudo dnf install bubblewrap`
- Arch: `sudo pacman -S bubblewrap`

## Architecture

The script creates a layered mount system:

1. **Base layer**: Entire filesystem mounted read-only with `/dev`, `/proc`, and a fresh `/tmp`
2. **Home directory**: Mounted read-only to protect personal files
3. **Sensitive path protection**: Blocks access to credentials/keys (unless `--include-sensitive`)
4. **Claude configs** (`~/.claude*`): Mounted read-write for persistence
5. **Current working directory**: Mounted read-write for project access
6. **Env protection** (optional): Blocks `.env*` files with `--protect-env`

### Protected Sensitive Paths

By default, the following are blocked:

- **Directories**: `~/.ssh`, `~/.gnupg`, `~/.aws`, `~/.config/gcloud`, `~/.kube`
- **Files**: `~/.netrc`, `~/.npmrc`, `~/.docker/config.json`, `~/.git-credentials`
- **Patterns**: `*_credentials`, `*_token`, `*.pem`, `*.key`, `*_secret`, `*.p12`, `*.pfx`

Session logs are saved as `claude_session_YYYY-MM-DD_HH-MM-SS.log` when using `--log`.
