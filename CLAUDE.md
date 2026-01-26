# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This repository provides a hardened sandbox script (`csandbox.sh`) for running Claude Code in an isolated environment using bubblewrap (bwrap).

## Usage

Run Claude Code in sandboxed mode:
```bash
./csandbox.sh [claude arguments]
```

Prerequisites: Install bubblewrap via `apt install bubblewrap` (or see https://github.com/containers/bubblewrap for other platforms).

## Architecture

The script creates a layered mount system:
1. Base layer: Entire filesystem mounted read-only with `/dev`, `/proc`, and a fresh `/tmp`
2. Home directory: Mounted read-only to protect personal files
3. Claude configs (`~/.claude*`): Mounted read-write for persistence
4. Current working directory: Mounted read-write for project access

Session logs are saved as `claude_session_TIMESTAMP.log`.
