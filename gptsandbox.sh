#!/bin/bash

# gptsandbox - Hardened sandbox for running Codex CLI
# https://github.com/containers/bubblewrap

VERSION="1.0.0"
SCRIPT_NAME=$(basename "$0")

# --- Help Function ---
show_help() {
    cat << EOF
${SCRIPT_NAME} - Run Codex CLI in a hardened sandbox using bubblewrap

DESCRIPTION:
    This script creates an isolated environment for running Codex CLI with
    filesystem protections. It uses bubblewrap (bwrap) to create a layered
    mount system that:

    • Mounts the entire filesystem read-only by default
    • Protects your home directory from modifications
    • Blocks access to sensitive files (SSH keys, credentials, tokens)
    • Allows read-write access only to Codex configs and current directory
    • Logs all session activity for review

USAGE:
    ${SCRIPT_NAME} [OPTIONS] [-- CODEX_ARGS...]

OPTIONS:
    -h, --help              Show this help message and exit
    -v, --version           Show version information and exit
    --install               Install to ~/.local/bin/gptsandbox
    --uninstall             Remove from ~/.local/bin/gptsandbox
    -p, --safe-mode         Enable safe mode (preserve Codex approval/sandbox
                            prompts; disables bypass mode)
    -s, --include-sensitive Disable sensitive file protection (NOT RECOMMENDED)
                            Allows access to SSH keys, credentials, tokens, etc.
    -l, --log               Enable session logging to file
    -e, --protect-env       Block .env files in working directory
    -R, --ro-dir <dir>      Mount a directory inside the working directory as
                            read-only. Can be specified multiple times.
                            Paths are relative to the working directory.
    --no-multi-agent        Disable default Codex multi-agent feature flag

CODEX ARGUMENTS:
    All Codex CLI options are supported. Use '--' to separate sandbox
    options from Codex options:

        ${SCRIPT_NAME} [SANDBOX_OPTIONS] -- [CODEX_OPTIONS]

    Common Codex options:
        -m, --model <model>        Select model
        -p, --profile <profile>    Use a Codex config profile
        -s, --sandbox <mode>       Set Codex sandbox mode
        -a, --ask-for-approval     Set Codex approval policy
        --full-auto                Workspace-write + on-request approvals

    Run 'codex --help' for the full list of Codex options.

EXAMPLES:
    ${SCRIPT_NAME}                    Run Codex with bypass mode in bwrap sandbox
    ${SCRIPT_NAME} --safe-mode        Run with permission prompts enabled
    ${SCRIPT_NAME} --log              Run with session logging enabled
    ${SCRIPT_NAME} --protect-env      Run with .env files blocked
    ${SCRIPT_NAME} -- -m gpt-5        Pass arguments to Codex
    ${SCRIPT_NAME} -- "analyze this project"   Start Codex with prompt
    ${SCRIPT_NAME} --ro-dir vendor        Protect vendor/ from writes
    ${SCRIPT_NAME} -R lib -R dist         Protect multiple directories
    ${SCRIPT_NAME} --no-multi-agent       Run without forcing multi-agent

READ-ONLY DIRECTORIES:
    Directories can be made read-only within the working directory using
    the -R/--ro-dir flag or a .gptsandbox.ro file in the working directory.

    The .gptsandbox.ro file lists one directory per line (relative to the
    working directory). Empty lines and lines starting with # are ignored.

    Example .gptsandbox.ro:
        # Third-party code - do not modify
        vendor
        node_modules
        dist

    Entries from .gptsandbox.ro are combined with any -R/--ro-dir flags.

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

    Codex CLI must be installed and available in PATH.

SESSION LOGS:
    Use -l or --log to enable session logging.
    Logs are saved to: codex_session_YYYY-MM-DD_HH-MM-SS.log

For more information: https://github.com/containers/bubblewrap
EOF
}

show_version() {
    echo "${SCRIPT_NAME} version ${VERSION}"
}

INSTALL_DIR="$HOME/.local/bin"
INSTALL_PATH="$INSTALL_DIR/gptsandbox"

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

    echo "✅ Installed! You can now run 'gptsandbox' from anywhere."
}

do_uninstall() {
    if [ -f "$INSTALL_PATH" ]; then
        echo "Removing $INSTALL_PATH..."
        rm "$INSTALL_PATH"
        echo "✅ Uninstalled."
    else
        echo "gptsandbox is not installed at $INSTALL_PATH"
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
LOG_FILE="codex_session_${TIMESTAMP}.log"

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
ENABLE_MULTI_AGENT=true
RO_DIRS=()
CODEX_ARGS=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help|-v|--version)
            # Already handled in early flag check
            shift
            ;;
        -p|--safe-mode)
            SAFE_MODE=true
            shift
            ;;
        -s|--include-sensitive)
            INCLUDE_SENSITIVE=true
            shift
            ;;
        -l|--log)
            ENABLE_LOG=true
            shift
            ;;
        -e|--protect-env)
            PROTECT_ENV=true
            shift
            ;;
        -R|--ro-dir)
            if [[ -z "${2:-}" ]]; then
                echo "Error: $1 requires a directory argument"
                exit 1
            fi
            RO_DIRS+=("$2")
            shift 2
            ;;
        --no-multi-agent)
            ENABLE_MULTI_AGENT=false
            shift
            ;;
        --)
            shift
            CODEX_ARGS+=("$@")
            break
            ;;
        *)
            CODEX_ARGS+=("$1")
            shift
            ;;
    esac
done

echo "🛡️  STARTING HARDENED MODE (BUBBLEWRAP)"
if [ "$SAFE_MODE" = true ]; then
    echo "🔐 Permission Mode: SAFE (will prompt for permissions)"
else
    echo "⚡ Permission Mode: BYPASS (--dangerously-bypass-approvals-and-sandbox)"
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
if [ "$ENABLE_MULTI_AGENT" = true ]; then
    echo "🤖 Multi-Agent: ENABLED (default --enable multi_agent)"
else
    echo "🤖 Multi-Agent: DISABLED (--no-multi-agent)"
fi
if [ ${#RO_DIRS[@]} -gt 0 ]; then
    echo "📖 Read-Only Dirs: ${#RO_DIRS[@]} specified (--ro-dir)"
fi
echo "---------------------------------------"

# --- 1. Build the Dynamic Mount List ---
# Start with base arguments: System RO, /dev, /proc, /tmp
BWRAP_ARGS="--ro-bind / / --dev /dev --proc /proc --tmpfs /tmp"

# Layer 1: Lock down the User's Home Directory (Read-Only)
BWRAP_ARGS="$BWRAP_ARGS --ro-bind "$HOME_DIR" "$HOME_DIR""

# Layer 1.5: Block sensitive directories/files (unless --include-sensitive is used)
if [ "$INCLUDE_SENSITIVE" = false ]; then
    BLOCKED_PATHS=()

    # Block sensitive directories
    for dir in "${SENSITIVE_DIRS[@]}"; do
        full_path="$HOME_DIR/$dir"
        if [ -e "$full_path" ]; then
            BWRAP_ARGS="$BWRAP_ARGS --tmpfs "$full_path""
            BLOCKED_PATHS+=("$full_path")
        fi
    done

    # Block sensitive files
    for file in "${SENSITIVE_FILES[@]}"; do
        full_path="$HOME_DIR/$file"
        if [ -e "$full_path" ]; then
            BWRAP_ARGS="$BWRAP_ARGS --ro-bind /dev/null "$full_path""
            BLOCKED_PATHS+=("$full_path")
        fi
    done

    # Scan for files matching sensitive patterns in home directory
    for pattern in "${SENSITIVE_PATTERNS[@]}"; do
        while IFS= read -r -d '' sensitive_file; do
            if [ -f "$sensitive_file" ]; then
                BWRAP_ARGS="$BWRAP_ARGS --ro-bind /dev/null "$sensitive_file""
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

# Layer 2: Unlock specific Codex config files (Read-Write)
for config_path in "$HOME_DIR"/.codex*; do
    if [ -e "$config_path" ]; then
        echo "   - [RW] $config_path"
        BWRAP_ARGS="$BWRAP_ARGS --bind "$config_path" "$config_path""
    fi
done

# Layer 3: Unlock the Current Working Directory (Read-Write)
echo "🔓 Unlocking Work Dir:"
echo "   - [RW] $CURRENT_DIR"
BWRAP_ARGS="$BWRAP_ARGS --bind "$CURRENT_DIR" "$CURRENT_DIR""

# Layer 3.5: Block sensitive files in the work directory
if [ "$INCLUDE_SENSITIVE" = false ]; then
    WORKDIR_BLOCKED=()
    for pattern in "${SENSITIVE_PATTERNS[@]}"; do
        while IFS= read -r -d '' sensitive_file; do
            if [ -f "$sensitive_file" ]; then
                BWRAP_ARGS="$BWRAP_ARGS --ro-bind /dev/null "$sensitive_file""
                WORKDIR_BLOCKED+=("$sensitive_file")
            fi
        done < <(find "$CURRENT_DIR" -maxdepth 3 -name "$pattern" -print0 2>/dev/null)
    done
    if [ ${#WORKDIR_BLOCKED[@]} -gt 0 ]; then
        echo "🚫 Protected Sensitive Files in Work Dir:"
        for blocked in "${WORKDIR_BLOCKED[@]}"; do
            echo "   - [BLOCKED] $blocked"
        done
    fi
fi

# Layer 3.6: Block .env files in the work directory
if [ "$PROTECT_ENV" = true ]; then
    ENV_BLOCKED=()
    while IFS= read -r -d '' env_file; do
        if [ -f "$env_file" ]; then
            BWRAP_ARGS="$BWRAP_ARGS --ro-bind /dev/null "$env_file""
            ENV_BLOCKED+=("$env_file")
        fi
    done < <(find "$CURRENT_DIR" -maxdepth 3 -name ".env*" -print0 2>/dev/null)
    if [ ${#ENV_BLOCKED[@]} -gt 0 ]; then
        echo "🚫 Protected .env Files in Work Dir:"
        for blocked in "${ENV_BLOCKED[@]}"; do
            echo "   - [BLOCKED] $blocked"
        done
    fi
fi

# Layer 3.7: Read-only directories in work dir
RO_FILE="$CURRENT_DIR/.gptsandbox.ro"
if [ -f "$RO_FILE" ]; then
    RO_FILE_COUNT=0
    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line%%#*}"
        line="${line%"${line##*[![:space:]]}"}"
        line="${line#"${line%%[![:space:]]*}"}"
        [[ -z "$line" ]] && continue
        RO_DIRS+=("$line")
        ((RO_FILE_COUNT++))
    done < "$RO_FILE"
    echo "📄 Loaded .gptsandbox.ro ($RO_FILE_COUNT entries)"
fi

if [ ${#RO_DIRS[@]} -gt 0 ]; then
    RO_APPLIED=()
    for ro_dir in "${RO_DIRS[@]}"; do
        if [[ "$ro_dir" = /* ]]; then
            ro_full="$ro_dir"
        else
            ro_full="$CURRENT_DIR/$ro_dir"
        fi
        if [ -e "$ro_full" ]; then
            ro_full=$(cd "$ro_full" && pwd)
        fi
        if [ ! -d "$ro_full" ]; then
            echo "⚠️  Warning: --ro-dir target does not exist or is not a directory: $ro_dir"
            continue
        fi
        if [[ "$ro_full" != "$CURRENT_DIR"/* ]]; then
            echo "⚠️  Warning: --ro-dir path is outside the working directory, skipping: $ro_dir"
            continue
        fi
        BWRAP_ARGS="$BWRAP_ARGS --ro-bind "$ro_full" "$ro_full""
        RO_APPLIED+=("$ro_full")
    done
    if [ ${#RO_APPLIED[@]} -gt 0 ]; then
        echo "📖 Read-Only Directories in Work Dir:"
        for ro_path in "${RO_APPLIED[@]}"; do
            echo "   - [RO] $ro_path"
        done
    fi
fi

# --- 2. Execute ---
echo "---------------------------------------"

# Construct the final command
if [ "$SAFE_MODE" = true ]; then
    FULL_CMD="bwrap $BWRAP_ARGS --share-net --new-session --die-with-parent codex"
else
    FULL_CMD="bwrap $BWRAP_ARGS --share-net --new-session --die-with-parent codex --dangerously-bypass-approvals-and-sandbox"
fi

if [ "$ENABLE_MULTI_AGENT" = true ]; then
    FULL_CMD="$FULL_CMD --enable multi_agent"
fi

FULL_CMD="$FULL_CMD ${CODEX_ARGS[*]}"

# Run the command
if [ "$ENABLE_LOG" = true ]; then
    script -q -e -c "$FULL_CMD" "$LOG_FILE"
    echo "---------------------------------------"
    echo "✅ Session finished. Log saved to: $LOG_FILE"
else
    eval "$FULL_CMD"
    echo "---------------------------------------"
    echo "✅ Session finished."
fi
