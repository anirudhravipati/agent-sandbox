#!/bin/bash

# sandbox - Hardened sandbox shell using bubblewrap
# https://github.com/containers/bubblewrap

VERSION="1.0.0"
SCRIPT_NAME=$(basename "$0")

# --- Help Function ---
show_help() {
    cat << EOF
${SCRIPT_NAME} - Run a sandboxed shell using bubblewrap

DESCRIPTION:
    This script creates an isolated shell environment with filesystem
    protections. It uses bubblewrap (bwrap) to create a layered mount
    system that:

    • Mounts the entire filesystem read-only by default
    • Protects your home directory from modifications
    • Blocks access to sensitive files (SSH keys, credentials, tokens)
    • Allows read-write access only to the current directory
    • Logs all session activity for review (optional)

USAGE:
    ${SCRIPT_NAME} [OPTIONS] [-- COMMAND...]

OPTIONS:
    -h, --help              Show this help message and exit
    -v, --version           Show version information and exit
    --install               Install to ~/.local/bin/sandbox
    --uninstall             Remove from ~/.local/bin/sandbox
    -s, --include-sensitive Disable sensitive file protection (NOT RECOMMENDED)
                            Allows access to SSH keys, credentials, tokens, etc.
    -l, --log               Enable session logging to file
    -e, --protect-env       Block .env files in working directory
    -n, --no-network        Disable network access inside sandbox

COMMAND:
    If no command is provided, an interactive shell is started.
    Use '--' to separate sandbox options from the command:

        ${SCRIPT_NAME} [OPTIONS] -- [COMMAND]

EXAMPLES:
    ${SCRIPT_NAME}                    Start sandboxed interactive shell
    ${SCRIPT_NAME} --log              Start with session logging enabled
    ${SCRIPT_NAME} --protect-env      Start with .env files blocked
    ${SCRIPT_NAME} --no-network       Start without network access
    ${SCRIPT_NAME} -- ls -la          Run a single command in sandbox
    ${SCRIPT_NAME} -e -- make build   Run make with .env protection

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

SESSION LOGS:
    Use -l or --log to enable session logging.
    Logs are saved to: sandbox_session_YYYY-MM-DD_HH-MM-SS.log

For more information: https://github.com/containers/bubblewrap
EOF
}

show_version() {
    echo "${SCRIPT_NAME} version ${VERSION}"
}

INSTALL_DIR="$HOME/.local/bin"
INSTALL_PATH="$INSTALL_DIR/sandbox"

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
        echo "Warning: $INSTALL_DIR is not in your PATH."
        echo "   Add this to your ~/.bashrc or ~/.zshrc:"
        echo ""
        echo "   export PATH=\"\$HOME/.local/bin:\$PATH\""
        echo ""
    fi

    echo "Installed! You can now run 'sandbox' from anywhere."
}

do_uninstall() {
    if [ -f "$INSTALL_PATH" ]; then
        echo "Removing $INSTALL_PATH..."
        rm "$INSTALL_PATH"
        echo "Uninstalled."
    else
        echo "sandbox is not installed at $INSTALL_PATH"
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

# --- Check for bubblewrap ---
if ! command -v bwrap &> /dev/null; then
    echo "Error: bubblewrap (bwrap) is not installed."
    echo ""
    echo "Install it with:"
    echo "  Debian/Ubuntu: sudo apt install bubblewrap"
    echo "  Fedora:        sudo dnf install bubblewrap"
    echo "  Arch:          sudo pacman -S bubblewrap"
    exit 1
fi

CURRENT_DIR=$(pwd)
HOME_DIR=$HOME
TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")
LOG_FILE="sandbox_session_${TIMESTAMP}.log"

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
INCLUDE_SENSITIVE=false
ENABLE_LOG=false
PROTECT_ENV=false
NO_NETWORK=false
USER_CMD=()
PARSING_CMD=false

for arg in "$@"; do
    if [ "$PARSING_CMD" = true ]; then
        USER_CMD+=("$arg")
        continue
    fi

    case "$arg" in
        -h|--help|-v|--version|--install|--uninstall)
            # Already handled in early flag check
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
        -n|--no-network)
            NO_NETWORK=true
            ;;
        --)
            PARSING_CMD=true
            ;;
        *)
            USER_CMD+=("$arg")
            ;;
    esac
done

echo "SANDBOX SHELL (BUBBLEWRAP)"
if [ "$INCLUDE_SENSITIVE" = true ]; then
    echo "Warning: Sensitive Protection: DISABLED (--include-sensitive)"
else
    echo "Sensitive Protection: ENABLED"
fi
if [ "$ENABLE_LOG" = true ]; then
    echo "Session Logging: ENABLED (--log)"
fi
if [ "$PROTECT_ENV" = true ]; then
    echo "Env Protection: ENABLED (--protect-env)"
fi
if [ "$NO_NETWORK" = true ]; then
    echo "Network Access: DISABLED (--no-network)"
else
    echo "Network Access: ENABLED"
fi
echo "---------------------------------------"

# --- 1. Build the Dynamic Mount List ---
# Start with base arguments: System RO, /dev, /proc, /tmp
# Note: --dev-bind /dev/pts is needed for interactive shell TTY support
BWRAP_ARGS="--ro-bind / / --dev /dev --dev-bind /dev/pts /dev/pts --proc /proc --tmpfs /tmp"

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
        echo "Protected Sensitive Paths:"
        for blocked in "${BLOCKED_PATHS[@]}"; do
            echo "   - [BLOCKED] $blocked"
        done
    fi
fi

# Layer 2: Unlock the Current Working Directory (Read-Write)
echo "Unlocking Work Dir:"
echo "   - [RW] $CURRENT_DIR"
BWRAP_ARGS="$BWRAP_ARGS --bind \"$CURRENT_DIR\" \"$CURRENT_DIR\""

# Layer 2.5: Block sensitive files in the work directory (unless --include-sensitive is used)
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
        echo "Protected Sensitive Files in Work Dir:"
        for blocked in "${WORKDIR_BLOCKED[@]}"; do
            echo "   - [BLOCKED] $blocked"
        done
    fi
fi

# Layer 2.6: Block .env files in the work directory (if --protect-env is used)
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
        echo "Protected .env Files in Work Dir:"
        for blocked in "${ENV_BLOCKED[@]}"; do
            echo "   - [BLOCKED] $blocked"
        done
    fi
fi

# --- 2. Execute ---
echo "---------------------------------------"

# Determine network access
if [ "$NO_NETWORK" = true ]; then
    NETWORK_ARG="--unshare-net"
else
    NETWORK_ARG="--share-net"
fi

# Determine command to run
if [ ${#USER_CMD[@]} -eq 0 ]; then
    # No command provided, start interactive shell
    SHELL_CMD="${SHELL:-/bin/bash}"
    echo "Starting sandboxed shell: $SHELL_CMD"
    echo "Type 'exit' to leave the sandbox."
    echo "---------------------------------------"
else
    SHELL_CMD="${USER_CMD[*]}"
fi

# Construct the final command
FULL_CMD="bwrap $BWRAP_ARGS $NETWORK_ARG --new-session --die-with-parent $SHELL_CMD"

# Run the command (with or without logging)
if [ "$ENABLE_LOG" = true ]; then
    # Run with 'script' to preserve TTY and logging
    script -q -e -c "$FULL_CMD" "$LOG_FILE"
    echo "---------------------------------------"
    echo "Session finished. Log saved to: $LOG_FILE"
else
    # Run directly without logging
    eval "$FULL_CMD"
    echo "---------------------------------------"
    echo "Session finished."
fi
