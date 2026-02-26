# Repository Guidelines

## Project Structure & Module Organization
This repository is a small Bash codebase focused on hardened sandbox launchers:
- `csandbox.sh`: sandbox wrapper for Claude Code
- `gsandbox.sh`: sandbox wrapper for Gemini CLI
- `gptsandbox.sh`: sandbox wrapper for Codex CLI
- `sandbox.sh`: generic shell sandbox wrapper
- `CLAUDE.md` and `GEMINI.md`: usage and behavior docs

There is no `src/` or `tests/` tree yet; scripts live at the repository root and should stay executable.

## Build, Test, and Development Commands
There is no compile step. Use these commands during development:
- `./csandbox.sh --help`, `./gsandbox.sh --help`, `./gptsandbox.sh --help`, `./sandbox.sh --help`: validate CLI help text
- `./csandbox.sh --version` (and equivalents): quick smoke check without running `bwrap`
- `bash -n *.sh`: syntax check all scripts
- `shellcheck *.sh`: static linting for shell best practices
- `./csandbox.sh --install` (or `gsandbox`/`gptsandbox`/`sandbox`): local install to `~/.local/bin`

## Coding Style & Naming Conventions
- Use Bash (`#!/bin/bash`) and 4-space indentation, matching existing scripts.
- Prefer uppercase for constants (for example `VERSION`, `INSTALL_DIR`) and lowercase for local variables.
- Keep option parsing explicit with `case` blocks.
- Preserve current user-facing patterns: `--help` sections, option table ordering, and clear security warnings.
- Run `shellcheck` before opening a PR.

## Testing Guidelines
No formal test harness exists; use repeatable script checks:
- Lint + syntax: `shellcheck *.sh && bash -n *.sh`
- Behavioral smoke tests: run `--help`, `--version`, `--install`, and `--uninstall` for each script.
- For sandbox behavior changes, verify sensitive-path blocking and optional flags like `--protect-env`, `--ro-dir`, or `--no-network`.

## Commit & Pull Request Guidelines
Recent history uses short, imperative commit messages (for example: `added -R option and .csandbox.ro support`, `fix`). Keep subject lines concise and action-oriented.

For PRs, include:
- What changed and why
- Scripts/docs touched
- Manual test commands and outcomes
- Any security-impact notes (mount rules, protected paths, env handling)

## Security & Configuration Tips
Default to least privilege: keep mounts read-only unless write access is required. Treat changes to sensitive path lists and `.env` protection as high-risk and document them clearly in PR descriptions.
