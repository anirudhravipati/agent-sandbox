#!/bin/bash

# Install bubblewrap using apt install bubblewrap or find specific instructions for your needs here https://github.com/containers/bubblewrap

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
CLAUDE_ARGS=()

for arg in "$@"; do
    case "$arg" in
        --safe-mode|-p|--prompt-permissions)
            SAFE_MODE=true
            ;;
        --include-sensitive|-s)
            INCLUDE_SENSITIVE=true
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

# Run with 'script' to preserve TTY and logging
script -q -e -c "$FULL_CMD" "$LOG_FILE"

echo "---------------------------------------"
echo "✅ Session finished. Log: $LOG_FILE"