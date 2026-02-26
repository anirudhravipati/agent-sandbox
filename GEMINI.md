# GEMINI.md

This file provides context and instructions for Gemini CLI when working in this repository.

## Project Overview

This project provides a collection of hardened sandbox scripts for running AI agents (like Claude Code) and generic shells in an isolated environment using `bubblewrap` (bwrap). The goal is to provide a secure execution environment that protects the host system's sensitive data while allowing the agent to perform its tasks.

### Main Technologies
- **Shell Scripting (Bash)**: The primary language used for the sandbox wrappers.
- **bubblewrap (bwrap)**: A low-level unprivileged sandboxing tool used to create isolated namespaces.
- **Claude Code**: The primary AI agent these scripts are designed to support.

### Architecture
The sandbox scripts create a layered mount system using `bubblewrap`:
1.  **Read-Only Root**: The entire filesystem is mounted as read-only.
2.  **Home Directory Protection**: The user's home directory is mounted read-only to prevent unauthorized modifications.
3.  **Sensitive Path Blocking**: Credentials, SSH keys, and other sensitive files (e.g., `~/.ssh`, `~/.aws`, `~/.npmrc`) are explicitly blocked or hidden using `tmpfs` or `/dev/null` mounts.
4.  **Selective Read-Write Access**: Only specific directories required for functionality (like Claude's configuration in `~/.claude*` and the current working directory) are mounted as read-write.
5.  **Environment Protection**: Optional blocking of `.env` files in the working directory.
6.  **Network Control**: Network access is shared by default for API connectivity but can be disabled for generic shell sandboxing.

## Building and Running

### Prerequisites
- **bubblewrap**: Must be installed on the host system.
    - Debian/Ubuntu: `sudo apt install bubblewrap`
    - Fedora: `sudo dnf install bubblewrap`
    - Arch: `sudo pacman -S bubblewrap`
- **Claude Code**: Required for `csandbox.sh`.

### Installation
You can install the scripts to `~/.local/bin` for easy access:
```bash
./csandbox.sh --install
./gsandbox.sh --install
./sandbox.sh --install
```

### Usage

#### csandbox.sh (for Claude Code)
```bash
# Run Claude in the sandbox with default settings
csandbox [OPTIONS] -- [CLAUDE_ARGS...]

# Example: Run Claude with a specific model and command
csandbox --model sonnet -- -c "analyze this project"
```

#### gsandbox.sh (for Gemini CLI)
```bash
# Run Gemini in the sandbox with default settings
gsandbox [OPTIONS] -- [GEMINI_ARGS...]

# Example: Run Gemini with a specific model and command
gsandbox -m flash -- -p "analyze this project"
```

#### sandbox.sh (for generic shell)
```bash
# Start a sandboxed interactive shell
sandbox

# Run a single command in the sandbox
sandbox -- ls -la
```

### Key Commands
- `--install`: Installs the script to `~/.local/bin`.
- `--uninstall`: Removes the script from `~/.local/bin`.
- `-l, --log`: Enables session logging to a file.
- `-p, --safe-mode`: (csandbox only) Enables permission prompts inside Claude.
- `-R, --ro-dir <dir>`: (csandbox only) Mounts a specific subdirectory as read-only.

## Development Conventions

- **Security First**: Any changes to the scripts should prioritize system integrity and sensitive data protection.
- **Bash Best Practices**: Use `shellcheck` to validate script changes. Ensure portability across Linux distributions.
- **Explicit Mounts**: Always favor explicit read-only mounts unless read-write is strictly necessary for functionality.
- **Documentation**: Maintain consistency between `CLAUDE.md`, `GEMINI.md`, and the scripts' help output.

## Key Files
- `csandbox.sh`: The core hardened wrapper for Claude Code.
- `gsandbox.sh`: The hardened wrapper for Gemini CLI.
- `sandbox.sh`: A general-purpose hardened shell wrapper.
- `CLAUDE.md`: Specific instructions and context for Claude Code.
- `.csandbox.ro`: Optional configuration file to define read-only directories within a project.
- `.gsandbox.ro`: Optional configuration file for Gemini sandbox read-only directories.
