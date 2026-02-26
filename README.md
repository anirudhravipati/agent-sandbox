# Hardened Sandbox Wrappers

A set of Bash wrappers that run AI CLIs and shell commands inside a hardened `bubblewrap` sandbox.

## Scripts

- `csandbox.sh`: run Claude Code in a sandbox
- `gsandbox.sh`: run Gemini CLI in a sandbox
- `gptsandbox.sh`: run Codex CLI in a sandbox
- `sandbox.sh`: run a generic shell/command in a sandbox

## Shared Security Model

All wrappers apply these defaults:
- read-only root filesystem
- read-only `$HOME`
- sensitive path blocking (`~/.ssh`, `~/.aws`, `~/.netrc`, `*.pem`, `*_token`, etc.)
- read-write mount of current working directory
- optional `.env` masking with `--protect-env`
- optional session logging with `--log`

## Feature Comparison

| Script | Target Binary | Safe Mode | Extra Options | RO File |
|---|---|---|---|---|
| `csandbox.sh` | `claude` | `--safe-mode` | `--browser`, `--no-teams` | `.csandbox.ro` |
| `gsandbox.sh` | `gemini` | `--safe-mode` | (safe mode disables `--yolo`) | `.gsandbox.ro` |
| `gptsandbox.sh` | `codex` | `--safe-mode` | (safe mode disables Codex bypass flag) | `.gptsandbox.ro` |
| `sandbox.sh` | shell command | n/a | `--no-network` | n/a |

## Prerequisites

Install `bubblewrap`:

```bash
# Debian/Ubuntu
sudo apt install bubblewrap
# Fedora
sudo dnf install bubblewrap
# Arch
sudo pacman -S bubblewrap
```

Install the target CLI(s): `claude`, `gemini`, and/or `codex`.

## Installation

```bash
./csandbox.sh --install
./gsandbox.sh --install
./gptsandbox.sh --install
./sandbox.sh --install
```

Add local bin to `PATH` if needed:

```bash
export PATH="$HOME/.local/bin:$PATH"
```

## Usage

```bash
# Claude
csandbox -- --model sonnet

# Gemini
gsandbox -- -m flash

# Codex
gptsandbox -- -m gpt-5

# Generic shell command
sandbox -- ls -la
```

Use `--help` on any script for full options.

## Development

```bash
bash -n *.sh
shellcheck *.sh
```

Keep script help text and docs in sync when adding/changing flags.
