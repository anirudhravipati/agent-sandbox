# CLAUDE.md

This file provides guidance to Claude Code when working in this repository.

## Repository Overview

This project contains hardened `bubblewrap` wrappers for multiple CLIs and a generic shell:

- `csandbox.sh`: Claude Code wrapper
- `gsandbox.sh`: Gemini CLI wrapper
- `gptsandbox.sh`: Codex CLI wrapper
- `sandbox.sh`: generic shell wrapper

All scripts follow the same security model: read-only root filesystem, read-only home by default, sensitive path blocking, and selective read-write mounts for tool configs and the current working directory.

## Script Matrix

| Script | Target | Default Mode | Config Mount | RO Config File |
|---|---|---|---|---|
| `csandbox.sh` | Claude Code | skip-permissions | `~/.claude*` | `.csandbox.ro` |
| `gsandbox.sh` | Gemini CLI | `--yolo` | `~/.gemini*` | `.gsandbox.ro` |
| `gptsandbox.sh` | Codex CLI | `--dangerously-bypass-approvals-and-sandbox` | `~/.codex*` | `.gptsandbox.ro` |
| `sandbox.sh` | shell commands | interactive shell | none | n/a |

## Common Usage

```bash
./csandbox.sh --help
./gsandbox.sh --help
./gptsandbox.sh --help
./sandbox.sh --help
```

Install wrappers into `~/.local/bin`:

```bash
./csandbox.sh --install
./gsandbox.sh --install
./gptsandbox.sh --install
./sandbox.sh --install
```

If needed:

```bash
export PATH="$HOME/.local/bin:$PATH"
```

## Key Security Features

- Blocks sensitive paths by default: `~/.ssh`, `~/.gnupg`, `~/.aws`, `~/.kube`, `~/.netrc`, `~/.npmrc`, `~/.git-credentials`, key/token-like file patterns.
- Optional `.env` masking with `--protect-env`.
- Optional per-project read-only directories via `-R/--ro-dir` and `.csandbox.ro`/`.gsandbox.ro`/`.gptsandbox.ro`.
- Optional session logging via `--log` to timestamped files.

## Development Notes

- Keep security defaults conservative.
- Keep script `--help` output and docs synchronized.
- Validate changes with:

```bash
bash -n *.sh
shellcheck *.sh
```
