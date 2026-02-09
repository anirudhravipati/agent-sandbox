#!/bin/bash

# csandbox - Hardened sandbox for running Claude Code
# https://github.com/containers/bubblewrap

VERSION="1.0.0"
SCRIPT_NAME=$(basename "$0")

# --- Help Function ---
show_help() {
    cat << EOF
${SCRIPT_NAME} - Run Claude Code in a hardened sandbox using bubblewrap

DESCRIPTION:
    This script creates an isolated environment for running Claude Code with
    filesystem protections. It uses bubblewrap (bwrap) to create a layered
    mount system that:

    • Mounts the entire filesystem read-only by default
    • Protects your home directory from modifications
    • Blocks access to sensitive files (SSH keys, credentials, tokens)
    • Allows read-write access only to Claude configs and current directory
    • Logs all session activity for review

USAGE:
    ${SCRIPT_NAME} [OPTIONS] [-- CLAUDE_ARGS...]

OPTIONS:
    -h, --help              Show this help message and exit
    -v, --version           Show version information and exit
    --install               Install to ~/.local/bin/csandbox
    --uninstall             Remove from ~/.local/bin/csandbox
    -p, --safe-mode         Enable safe mode (prompt for permissions)
        --prompt-permissions  Same as --safe-mode
    -s, --include-sensitive Disable sensitive file protection (NOT RECOMMENDED)
                            Allows access to SSH keys, credentials, tokens, etc.
    -l, --log               Enable session logging to file
    -e, --protect-env       Block .env files in working directory
    -b, --browser           Enable agent-browser support inside sandbox
                            Mounts the agent-browser socket directory read-write
    -t, --no-teams          Disable experimental agent teams
                            (Agent teams are enabled by default)

CLAUDE ARGUMENTS:
    All Claude Code options are supported. Use '--' to separate sandbox
    options from Claude options:

        ${SCRIPT_NAME} [SANDBOX_OPTIONS] -- [CLAUDE_OPTIONS]

    Common Claude options:
        --model <model>       Select model (e.g., opus, sonnet)
        -c, --command <cmd>   Run a single command and exit
        --print               Print response without interactive mode
        -r, --resume          Resume previous conversation

    Run 'claude --help' for the full list of Claude options.

EXAMPLES:
    ${SCRIPT_NAME}                    Run Claude in sandbox with default settings
    ${SCRIPT_NAME} --safe-mode        Run with permission prompts enabled
    ${SCRIPT_NAME} --log              Run with session logging enabled
    ${SCRIPT_NAME} --protect-env      Run with .env files blocked
    ${SCRIPT_NAME} -- --model opus    Pass arguments to Claude
    ${SCRIPT_NAME} --browser             Run with agent-browser support
    ${SCRIPT_NAME} --no-teams            Run with agent teams disabled
    ${SCRIPT_NAME} -p -- -c "task"    Safe mode with a specific Claude command

PROTECTED PATHS:
    The following are blocked by default (use --include-sensitive to allow):

    Directories: ~/.ssh, ~/.gnupg, ~/.aws, ~/.config/gcloud, ~/.kube
    Files:       ~/.netrc, ~/.npmrc, ~/.docker/config.json, ~/.git-credentials
    Patterns:    *_credentials, *_token, *.pem, *.key, *_secret, *.p12, *.pfx

PREREQUISITES:
    Install bubblewrap:
        Debian/Ubuntu: sudo apt install bubblewrap
        Fedora:        sudo dnf install bubblewrap
        Arch:          sudo pacman -S bubblewrap
        macOS:         See https://github.com/containers/bubblewrap

    Claude Code must be installed and available in PATH.
    agent-browser (optional): npm install -g agent-browser && agent-browser install

AGENT TEAMS:
    The sandbox automatically enables the experimental agent teams feature
    by setting CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1 inside the sandbox.
    This allows Claude to coordinate multiple instances working in parallel.

SESSION LOGS:
    Use -l or --log to enable session logging.
    Logs are saved to: claude_session_YYYY-MM-DD_HH-MM-SS.log

For more information: https://github.com/containers/bubblewrap
EOF
}

show_version() {
    echo "${SCRIPT_NAME} version ${VERSION}"
}

INSTALL_DIR="$HOME/.local/bin"
INSTALL_PATH="$INSTALL_DIR/csandbox"

do_install() {
    # Get the actual script path (resolve symlinks)
    local script_path
    script_path="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"

    # Create install directory if needed
    if [ ! -d "$INSTALL_DIR" ]; then
        echo "Creating $INSTALL_DIR..."
        mkdir -p "$INSTALL_DIR"
    fi

    # Copy script
    echo "Installing to $INSTALL_PATH..."
    cp "$script_path" "$INSTALL_PATH"
    chmod +x "$INSTALL_PATH"

    # Check if ~/.local/bin is in PATH
    if [[ ":$PATH:" != *":$INSTALL_DIR:"* ]]; then
        echo ""
        echo "⚠️  $INSTALL_DIR is not in your PATH."
        echo "   Add this to your ~/.bashrc or ~/.zshrc:"
        echo ""
        echo "   export PATH=\"\$HOME/.local/bin:\$PATH\""
        echo ""
    fi

    echo "✅ Installed! You can now run 'csandbox' from anywhere."
}

do_uninstall() {
    if [ -f "$INSTALL_PATH" ]; then
        echo "Removing $INSTALL_PATH..."
        rm "$INSTALL_PATH"
        echo "✅ Uninstalled."
    else
        echo "csandbox is not installed at $INSTALL_PATH"
        exit 1
    fi
}

# --- Early Flag Check (help/version/install) ---
for arg in "$@"; do
    case "$arg" in
        -h|--help)
            show_help
            exit 0
            ;;
        -v|--version)
            show_version
            exit 0
            ;;
        --install)
            do_install
            exit 0
            ;;
        --uninstall)
            do_uninstall
            exit 0
            ;;
    esac
done

CURRENT_DIR=$(pwd)
HOME_DIR=$HOME
TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")
LOG_FILE="claude_session_${TIMESTAMP}.log"

# --- Sensitive Path Protection ---
# Directories that should never be mounted (contain credentials/keys)
SENSITIVE_DIRS=(
    ".ssh"
    ".gnupg"
    ".aws"
    ".config/gcloud"
    ".kube"
)

# Files that should never be mounted (contain tokens/credentials)
SENSITIVE_FILES=(
    ".netrc"
    ".npmrc"
    ".docker/config.json"
    ".git-credentials"
)

# File patterns that indicate sensitive content
SENSITIVE_PATTERNS=(
    "*_credentials"
    "*_token"
    "*.pem"
    "*.key"
    "*_secret"
    "*.p12"
    "*.pfx"
)

# Function to check if a path matches sensitive patterns
is_sensitive_path() {
    local path="$1"
    local basename
    basename=$(basename "$path")

    # Check against sensitive directories
    for dir in "${SENSITIVE_DIRS[@]}"; do
        if [[ "$path" == "$HOME_DIR/$dir" || "$path" == "$HOME_DIR/$dir/"* ]]; then
            return 0
        fi
    done

    # Check against sensitive files
    for file in "${SENSITIVE_FILES[@]}"; do
        if [[ "$path" == "$HOME_DIR/$file" ]]; then
            return 0
        fi
    done

    # Check against sensitive patterns
    for pattern in "${SENSITIVE_PATTERNS[@]}"; do
        # shellcheck disable=SC2254
        case "$basename" in
            $pattern)
                return 0
                ;;
        esac
    done

    return 1
}

# --- Parse Arguments ---
SAFE_MODE=false
INCLUDE_SENSITIVE=false
ENABLE_LOG=false
PROTECT_ENV=false
ENABLE_BROWSER=false
DISABLE_TEAMS=false
CLAUDE_ARGS=()

for arg in "$@"; do
    case "$arg" in
        -h|--help|-v|--version)
            # Already handled in early flag check
            ;;
        -p|--safe-mode|--prompt-permissions)
            SAFE_MODE=true
            ;;
        -s|--include-sensitive)
            INCLUDE_SENSITIVE=true
            ;;
        -l|--log)
            ENABLE_LOG=true
            ;;
        -e|--protect-env)
            PROTECT_ENV=true
            ;;
        -b|--browser)
            ENABLE_BROWSER=true
            ;;
        -t|--no-teams)
            DISABLE_TEAMS=true
            ;;
        *)
            CLAUDE_ARGS+=("$arg")
            ;;
    esac
done

echo "🛡️  STARTING HARDENED MODE (BUBBLEWRAP)"
if [ "$SAFE_MODE" = true ]; then
    echo "🔐 Permission Mode: SAFE (will prompt for permissions)"
else
    echo "⚡ Permission Mode: SKIP (--dangerously-skip-permissions)"
fi
if [ "$INCLUDE_SENSITIVE" = true ]; then
    echo "⚠️  Sensitive Protection: DISABLED (--include-sensitive)"
else
    echo "🔒 Sensitive Protection: ENABLED"
fi
if [ "$ENABLE_LOG" = true ]; then
    echo "📝 Session Logging: ENABLED (--log)"
fi
if [ "$PROTECT_ENV" = true ]; then
    echo "🔐 Env Protection: ENABLED (--protect-env)"
fi
if [ "$ENABLE_BROWSER" = true ]; then
    echo "🌐 Agent-Browser: ENABLED (--browser)"
fi
echo "---------------------------------------"

# --- 1. Build the Dynamic Mount List ---
# Start with base arguments: System RO, /dev, /proc, /tmp
BWRAP_ARGS="--ro-bind / / --dev /dev --proc /proc --tmpfs /tmp"

# Layer 1: Lock down the User's Home Directory (Read-Only)
# This prevents deletion of personal files.
BWRAP_ARGS="$BWRAP_ARGS --ro-bind \"$HOME_DIR\" \"$HOME_DIR\""

# Layer 1.5: Block sensitive directories/files (unless --include-sensitive is used)
if [ "$INCLUDE_SENSITIVE" = false ]; then
    BLOCKED_PATHS=()

    # Block sensitive directories
    for dir in "${SENSITIVE_DIRS[@]}"; do
        full_path="$HOME_DIR/$dir"
        if [ -e "$full_path" ]; then
            BWRAP_ARGS="$BWRAP_ARGS --tmpfs \"$full_path\""
            BLOCKED_PATHS+=("$full_path")
        fi
    done

    # Block sensitive files
    for file in "${SENSITIVE_FILES[@]}"; do
        full_path="$HOME_DIR/$file"
        if [ -e "$full_path" ]; then
            # For files, we need to use --ro-bind /dev/null to effectively hide them
            BWRAP_ARGS="$BWRAP_ARGS --ro-bind /dev/null \"$full_path\""
            BLOCKED_PATHS+=("$full_path")
        fi
    done

    # Scan for files matching sensitive patterns in home directory
    for pattern in "${SENSITIVE_PATTERNS[@]}"; do
        while IFS= read -r -d '' sensitive_file; do
            if [ -f "$sensitive_file" ]; then
                BWRAP_ARGS="$BWRAP_ARGS --ro-bind /dev/null \"$sensitive_file\""
                BLOCKED_PATHS+=("$sensitive_file")
            fi
        done < <(find "$HOME_DIR" -maxdepth 2 -name "$pattern" -print0 2>/dev/null)
    done

    # Print blocked paths if any were found
    if [ ${#BLOCKED_PATHS[@]} -gt 0 ]; then
        echo "🚫 Protected Sensitive Paths:"
        for blocked in "${BLOCKED_PATHS[@]}"; do
            echo "   - [BLOCKED] $blocked"
        done
    fi
fi

echo "🔓 Unlocking Configs:"

# Layer 2: Unlock specific Claude config files (Read-Write)
# We specifically look for the directory AND the json files you listed.
# The glob .claude* catches: .claude (dir), .claude.json, .claude.json.backup
for config_path in "$HOME_DIR"/.claude*; do
    if [ -e "$config_path" ]; then
        echo "   - [RW] $config_path"
        # Mount the file/folder over itself as Read-Write
        BWRAP_ARGS="$BWRAP_ARGS --bind \"$config_path\" \"$config_path\""
    fi
done

# Layer 3: Unlock the Current Working Directory (Read-Write)
echo "🔓 Unlocking Work Dir:"
echo "   - [RW] $CURRENT_DIR"
BWRAP_ARGS="$BWRAP_ARGS --bind \"$CURRENT_DIR\" \"$CURRENT_DIR\""

# Layer 3.5: Block sensitive files in the work directory (unless --include-sensitive is used)
if [ "$INCLUDE_SENSITIVE" = false ]; then
    WORKDIR_BLOCKED=()

    # Scan for files matching sensitive patterns in work directory
    for pattern in "${SENSITIVE_PATTERNS[@]}"; do
        while IFS= read -r -d '' sensitive_file; do
            if [ -f "$sensitive_file" ]; then
                BWRAP_ARGS="$BWRAP_ARGS --ro-bind /dev/null \"$sensitive_file\""
                WORKDIR_BLOCKED+=("$sensitive_file")
            fi
        done < <(find "$CURRENT_DIR" -maxdepth 3 -name "$pattern" -print0 2>/dev/null)
    done

    # Print blocked work directory paths if any were found
    if [ ${#WORKDIR_BLOCKED[@]} -gt 0 ]; then
        echo "🚫 Protected Sensitive Files in Work Dir:"
        for blocked in "${WORKDIR_BLOCKED[@]}"; do
            echo "   - [BLOCKED] $blocked"
        done
    fi
fi

# Layer 3.6: Block .env files in the work directory (if --protect-env is used)
if [ "$PROTECT_ENV" = true ]; then
    ENV_BLOCKED=()

    # Scan for .env* files in work directory
    while IFS= read -r -d '' env_file; do
        if [ -f "$env_file" ]; then
            BWRAP_ARGS="$BWRAP_ARGS --ro-bind /dev/null \"$env_file\""
            ENV_BLOCKED+=("$env_file")
        fi
    done < <(find "$CURRENT_DIR" -maxdepth 3 -name ".env*" -print0 2>/dev/null)

    # Print blocked .env paths if any were found
    if [ ${#ENV_BLOCKED[@]} -gt 0 ]; then
        echo "🚫 Protected .env Files in Work Dir:"
        for blocked in "${ENV_BLOCKED[@]}"; do
            echo "   - [BLOCKED] $blocked"
        done
    fi
fi

# Layer 4: Agent-browser support (if --browser is used)
if [ "$ENABLE_BROWSER" = true ]; then
    # Determine the socket directory agent-browser will use
    if [ -n "$AGENT_BROWSER_SOCKET_DIR" ]; then
        AB_SOCKET_DIR="$AGENT_BROWSER_SOCKET_DIR"
    elif [ -n "$XDG_RUNTIME_DIR" ]; then
        AB_SOCKET_DIR="$XDG_RUNTIME_DIR/agent-browser"
    else
        AB_SOCKET_DIR="$HOME_DIR/.agent-browser"
    fi

    # Create the socket directory if it doesn't exist
    mkdir -p "$AB_SOCKET_DIR" 2>/dev/null

    echo "🌐 Unlocking Agent-Browser:"
    echo "   - [RW] $AB_SOCKET_DIR (socket dir)"
    BWRAP_ARGS="$BWRAP_ARGS --bind \"$AB_SOCKET_DIR\" \"$AB_SOCKET_DIR\""
fi

# Layer 5: Enable experimental agent teams (unless --no-teams)
if [ "$DISABLE_TEAMS" = true ]; then
    echo "🤖 Agent Teams: DISABLED (--no-teams)"
else
    BWRAP_ARGS="$BWRAP_ARGS --setenv CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS 1"
    echo "🤖 Agent Teams: ENABLED (CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1)"
fi

# --- 2. Execute ---
echo "---------------------------------------"

# Construct the final command
# --share-net: Required for API access
# --dangerously-skip-permissions: Used for autonomous mode (disabled with --safe-mode)
if [ "$SAFE_MODE" = true ]; then
    FULL_CMD="bwrap $BWRAP_ARGS --share-net --new-session --die-with-parent claude ${CLAUDE_ARGS[*]}"
else
    FULL_CMD="bwrap $BWRAP_ARGS --share-net --new-session --die-with-parent claude --dangerously-skip-permissions ${CLAUDE_ARGS[*]}"
fi

# Run the command (with or without logging)
if [ "$ENABLE_LOG" = true ]; then
    # Run with 'script' to preserve TTY and logging
    script -q -e -c "$FULL_CMD" "$LOG_FILE"
    echo "---------------------------------------"
    echo "✅ Session finished. Log saved to: $LOG_FILE"
else
    # Run directly without logging
    eval "$FULL_CMD"
    echo "---------------------------------------"
    echo "✅ Session finished."
fi