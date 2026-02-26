# GEMINI.md

This file provides context and instructions for Gemini CLI when working in this repository.

## Project Overview

This repository provides hardened sandbox launchers for AI CLIs and a generic shell, built with Bash and `bubblewrap`:

- `csandbox.sh` for Claude Code
- `gsandbox.sh` for Gemini CLI
- `gptsandbox.sh` for Codex CLI
- `sandbox.sh` for generic shell execution

## Architecture (Shared Across Scripts)

1. Mount filesystem read-only by default.
2. Mount home directory read-only.
3. Block sensitive files/directories/patterns (credentials, keys, tokens).
4. Re-enable only required read-write paths (tool config + current project directory).
5. Optionally block `.env*` files in project (`--protect-env`).
6. Optionally log sessions (`--log`).

## Build and Run

### Prerequisites
- `bubblewrap` installed (`bwrap` in `PATH`)
- Target CLI installed (`claude`, `gemini`, or `codex` depending on wrapper)

### Install

```bash
./csandbox.sh --install
./gsandbox.sh --install
./gptsandbox.sh --install
./sandbox.sh --install
```

### Usage Examples

```bash
# Claude
csandbox -- --model sonnet

# Gemini
gsandbox -- -m flash

# Codex
gptsandbox -- -m gpt-5

# Generic shell
sandbox -- ls -la
```

## Script-Specific Options

- `csandbox.sh`: `--browser`, `--no-teams`, `.csandbox.ro`
- `gsandbox.sh`: `--safe-mode` (disables `--yolo`), `.gsandbox.ro`
- `gptsandbox.sh`: `--safe-mode` (disables Codex bypass flag), `.gptsandbox.ro`
- `sandbox.sh`: `--no-network` for offline shell sessions

## Development Conventions

- Security-first changes only; default to least privilege.
- Keep docs and `--help` output aligned.
- Validate with:

```bash
bash -n *.sh
shellcheck *.sh
```
