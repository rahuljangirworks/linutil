#!/bin/sh -e

# Description: Install & configure Claude Code CLI with Z.AI GLM models
# Models: glm-5.1 (Sonnet/Opus), glm-4.5-air (Haiku)
# Works on: Arch, Debian, Fedora, openSUSE, Void, Alpine, Solus, macOS

. ../common-script.sh

checkEnv

# ─── Globals ──────────────────────────────────────────────────────────────────
NPM_GLOBAL="$HOME/.npm-global"
CLAUDE_DIR="$HOME/.claude"
SETTINGS_FILE="$CLAUDE_DIR/settings.json"
ZAI_BASE_URL="https://api.z.ai/api/anthropic"
SONNET_MODEL="glm-5.1"
OPUS_MODEL="glm-5.1"
HAIKU_MODEL="glm-4.5-air"

# ─── Detect shell RC file ────────────────────────────────────────────────────
detect_shell_rc() {
    case "$SHELL" in
        */zsh)  echo "$HOME/.zshrc" ;;
        */bash) echo "$HOME/.bashrc" ;;
        */fish) echo "$HOME/.config/fish/config.fish" ;;
        *)      echo "$HOME/.profile" ;;
    esac
}

# ─── Header ──────────────────────────────────────────────────────────────────
clear
printf "%b\n" "${CYAN}=================================================================${RC}"
printf "%b\n" "${YELLOW}   Rahul's Claude Code + Z.AI GLM Setup                         ${RC}"
printf "%b\n" "${CYAN}=================================================================${RC}"
printf "%b\n" "${GREEN}  Model: glm-5.1 (Sonnet/Opus) | glm-4.5-air (Haiku)${RC}"
printf "%b\n" "${GREEN}  Provider: Z.AI (api.z.ai)${RC}"
printf "%b\n" "${CYAN}=================================================================${RC}"
echo ""

# ─── Step 1: Get Z.AI API Key ────────────────────────────────────────────────
get_api_key() {
    printf "%b\n" "${CYAN}━━━ [1/6] Z.AI API Key ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RC}"

    # Check if key already exists in settings
    EXISTING_KEY=""
    if [ -f "$SETTINGS_FILE" ]; then
        EXISTING_KEY=$(grep -o '"apiKeyHelper"[[:space:]]*:[[:space:]]*"echo[[:space:]]*\([^"]*\)"' "$SETTINGS_FILE" 2>/dev/null | sed 's/.*"echo[[:space:]]*//' | sed 's/"//g' | tr -d ' ')
    fi

    if [ -n "$EXISTING_KEY" ]; then
        printf "%b\n" "${GREEN}[✓] Existing Z.AI API key found in settings${RC}"
        printf "%b " "${CYAN}Use existing key? [Y/n]:${RC}"
        read -r USE_EXISTING
        case "$USE_EXISTING" in
            n|N|no|NO)
                EXISTING_KEY=""
                ;;
            *)
                API_KEY="$EXISTING_KEY"
                ;;
        esac
    fi

    if [ -z "$API_KEY" ]; then
        printf "%b\n" "${YELLOW}Enter your Z.AI API Key (input hidden):${RC}"
        # Use stty to hide input on both Linux and macOS
        if [ -t 0 ]; then
            stty -echo 2>/dev/null || true
            read -r API_KEY
            stty echo 2>/dev/null || true
            echo ""
        else
            read -r API_KEY
        fi

        if [ -z "$API_KEY" ]; then
            printf "%b\n" "${RED}[✗] API Key is required! Exiting.${RC}"
            exit 1
        fi
    fi

    # Basic format validation
    if ! echo "$API_KEY" | grep -qE '^[a-zA-Z0-9._-]+$'; then
        printf "%b\n" "${RED}[✗] API Key contains invalid characters! Exiting.${RC}"
        exit 1
    fi

    printf "%b\n" "${GREEN}[✓] API Key accepted${RC}"
}

# ─── Step 2: Create ~/.claude/settings.json ──────────────────────────────────
create_settings() {
    printf "%b\n" "${CYAN}━━━ [2/6] Claude Code Settings ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RC}"

    mkdir -p "$CLAUDE_DIR"

    # Backup existing settings if present
    if [ -f "$SETTINGS_FILE" ]; then
        BACKUP="$SETTINGS_FILE.bak.$(date +%Y%m%d%H%M%S)"
        cp "$SETTINGS_FILE" "$BACKUP"
        printf "%b\n" "${YELLOW}[~] Backed up existing settings to $(basename "$BACKUP")${RC}"
    fi

    # Write new settings.json
    cat > "$SETTINGS_FILE" <<EOF
{
  "apiKeyHelper": "echo $API_KEY",
  "env": {
    "ANTHROPIC_BASE_URL": "$ZAI_BASE_URL",
    "ANTHROPIC_DEFAULT_SONNET_MODEL": "$SONNET_MODEL",
    "ANTHROPIC_DEFAULT_OPUS_MODEL": "$OPUS_MODEL",
    "ANTHROPIC_DEFAULT_HAIKU_MODEL": "$HAIKU_MODEL"
  }
}
EOF

    chmod 600 "$SETTINGS_FILE"
    printf "%b\n" "${GREEN}[✓] Settings written to $SETTINGS_FILE${RC}"
    printf "%b\n" "${GREEN}    apiKeyHelper:    configured${RC}"
    printf "%b\n" "${GREEN}    Base URL:        $ZAI_BASE_URL${RC}"
    printf "%b\n" "${GREEN}    Sonnet/Opus:     $SONNET_MODEL${RC}"
    printf "%b\n" "${GREEN}    Haiku:           $HAIKU_MODEL${RC}"
}

# ─── Step 3: Add exports to shell RC ─────────────────────────────────────────
configure_shell() {
    printf "%b\n" "${CYAN}━━━ [3/6] Shell Environment ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RC}"

    # Determine which RC files to update
    RC_FILES=""
    if [ -f "$HOME/.zshrc" ]; then
        RC_FILES="$RC_FILES $HOME/.zshrc"
    fi
    if [ -f "$HOME/.bashrc" ]; then
        RC_FILES="$RC_FILES $HOME/.bashrc"
    fi
    if [ -f "$HOME/.bash_profile" ]; then
        RC_FILES="$RC_FILES $HOME/.bash_profile"
    fi
    # macOS uses .zprofile for login shells
    if [ "$(uname)" = "Darwin" ] && [ -f "$HOME/.zprofile" ]; then
        RC_FILES="$RC_FILES $HOME/.zprofile"
    fi
    # Fallback: if no RC files exist, create the default one
    if [ -z "$RC_FILES" ]; then
        SHELL_RC=$(detect_shell_rc)
        touch "$SHELL_RC"
        RC_FILES="$SHELL_RC"
        printf "%b\n" "${YELLOW}[~] Created $(basename "$SHELL_RC")${RC}"
    fi

    # Remove any previous Z.AI / Claude GLM config blocks
    for rc_file in $RC_FILES; do
        if [ -f "$rc_file" ]; then
            # Remove old block markers and content between them
            sed -i '/# Z.AI Claude Code/,/# End Z.AI Claude Code/d' "$rc_file"
            # Also remove any standalone entries from older versions
            sed -i '/# ANTHROPIC_BASE_URL/d; /# ANTHROPIC_API_KEY/d; /# ANTHROPIC_DEFAULT_SONNET_MODEL/d; /# ANTHROPIC_DEFAULT_OPUS_MODEL/d; /# ANTHROPIC_DEFAULT_HAIKU_MODEL/d; /# CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC/d' "$rc_file"
            # Remove export lines for these specific vars (but not other content)
            sed -i '/export ANTHROPIC_BASE_URL="https:\/\/api\.z\.ai/d' "$rc_file"
            sed -i '/export ANTHROPIC_API_KEY=/d' "$rc_file"
            sed -i '/export ANTHROPIC_DEFAULT_SONNET_MODEL="glm-/d' "$rc_file"
            sed -i '/export ANTHROPIC_DEFAULT_OPUS_MODEL="glm-/d' "$rc_file"
            sed -i '/export ANTHROPIC_DEFAULT_HAIKU_MODEL="glm-/d' "$rc_file"
            sed -i '/export CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=/d' "$rc_file"
        fi
    done

    # Append new config block
    for rc_file in $RC_FILES; do
        cat >> "$rc_file" <<EOF

# Z.AI Claude Code — GLM Model Config (managed by linutil)
export ANTHROPIC_BASE_URL="$ZAI_BASE_URL"
export ANTHROPIC_API_KEY="$API_KEY"
export ANTHROPIC_DEFAULT_SONNET_MODEL="$SONNET_MODEL"
export ANTHROPIC_DEFAULT_OPUS_MODEL="$OPUS_MODEL"
export ANTHROPIC_DEFAULT_HAIKU_MODEL="$HAIKU_MODEL"
export CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1
# End Z.AI Claude Code
EOF
        printf "%b\n" "${GREEN}[✓] Environment configured in $(basename "$rc_file")${RC}"
    done

    # Also set /etc/profile.d/ for system-wide access (Linux only)
    if [ -d /etc/profile.d ] && [ "$(uname)" != "Darwin" ]; then
        printf "%b\n" "${CYAN}[*] Writing system-wide config to /etc/profile.d/...${RC}"
        TMP_CONF=$(mktemp)
        cat > "$TMP_CONF" <<EOF
# Z.AI Claude Code — System-wide GLM Config (managed by linutil)
export ANTHROPIC_BASE_URL="$ZAI_BASE_URL"
export ANTHROPIC_API_KEY="$API_KEY"
export ANTHROPIC_DEFAULT_SONNET_MODEL="$SONNET_MODEL"
export ANTHROPIC_DEFAULT_OPUS_MODEL="$OPUS_MODEL"
export ANTHROPIC_DEFAULT_HAIKU_MODEL="$HAIKU_MODEL"
export CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1
EOF
        "$ESCALATION_TOOL" mv "$TMP_CONF" /etc/profile.d/zai-claude.sh 2>/dev/null && \
        "$ESCALATION_TOOL" chmod 644 /etc/profile.d/zai-claude.sh 2>/dev/null && \
        printf "%b\n" "${GREEN}[✓] System-wide config written to /etc/profile.d/zai-claude.sh${RC}" || \
        printf "%b\n" "${YELLOW}[~] Could not write system-wide config (non-fatal)${RC}"
    fi
}

# ─── Step 4: Install Claude Code CLI ─────────────────────────────────────────
install_claude() {
    printf "%b\n" "${CYAN}━━━ [4/6] Claude Code CLI ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RC}"

    # Ensure Node.js & npm are available
    if ! command_exists npm; then
        printf "%b\n" "${YELLOW}[*] npm not found. Installing Node.js & npm...${RC}"
        case "$PACKAGER" in
            pacman)
                "$ESCALATION_TOOL" "$PACKAGER" -S --needed --noconfirm nodejs npm
                ;;
            apk)
                "$ESCALATION_TOOL" "$PACKAGER" add nodejs npm
                ;;
            xbps-install)
                "$ESCALATION_TOOL" "$PACKAGER" -Sy nodejs
                ;;
            nala|apt-get|apt)
                "$ESCALATION_TOOL" apt-get update
                "$ESCALATION_TOOL" apt-get install -y nodejs npm
                ;;
            dnf|zypper|eopkg)
                "$ESCALATION_TOOL" "$PACKAGER" install -y nodejs npm
                ;;
            *)
                # macOS fallback: try brew or direct install
                if [ "$(uname)" = "Darwin" ]; then
                    if command_exists brew; then
                        brew install node
                    else
                        printf "%b\n" "${RED}[✗] Cannot auto-install Node.js on macOS without Homebrew.${RC}"
                        printf "%b\n" "${YELLOW}    Install Homebrew first: /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\"${RC}"
                        exit 1
                    fi
                else
                    printf "%b\n" "${RED}[✗] Cannot auto-install Node.js. Please install manually.${RC}"
                    exit 1
                fi
                ;;
        esac
    fi

    # Setup npm global prefix for non-root users
    if [ "$(id -u)" != "0" ]; then
        if [ ! -d "$NPM_GLOBAL" ]; then
            mkdir -p "$NPM_GLOBAL"
            npm config set prefix "$NPM_GLOBAL"
        fi
        mkdir -p "$NPM_GLOBAL/bin"
        case ":$PATH:" in
            *:"$NPM_GLOBAL/bin":*) ;;
            *) export PATH="$NPM_GLOBAL/bin:$PATH" ;;
        esac
    fi

    # Check if Claude Code is already installed
    if command_exists claude; then
        CLAUDE_VER=$(claude --version 2>/dev/null || echo "installed")
        printf "%b\n" "${GREEN}[✓] Claude Code already installed — $CLAUDE_VER${RC}"
    else
        printf "%b\n" "${YELLOW}[*] Installing Claude Code CLI...${RC}"
        npm install -g @anthropic-ai/claude-code
        if command_exists claude; then
            CLAUDE_VER=$(claude --version 2>/dev/null || echo "installed")
            printf "%b\n" "${GREEN}[✓] Claude Code installed — $CLAUDE_VER${RC}"
        else
            printf "%b\n" "${RED}[✗] Claude Code installation failed!${RC}"
            printf "%b\n" "${YELLOW}    Try manually: npm install -g @anthropic-ai/claude-code${RC}"
            exit 1
        fi
    fi
}

# ─── Step 5: Ensure PATH persistence ─────────────────────────────────────────
persist_paths() {
    printf "%b\n" "${CYAN}━━━ [5/6] PATH Persistence ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RC}"

    PATH_BLOCK="
# Claude Code PATH (managed by linutil)
case \":\$PATH:\" in
    *:\"\$HOME/.npm-global/bin\":*) ;;
    *) export PATH=\"\$HOME/.npm-global/bin:\$PATH\" ;;
esac"

    for rc_file in "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.profile" "$HOME/.bash_profile"; do
        if [ -f "$rc_file" ]; then
            if ! grep -q "Claude Code PATH" "$rc_file"; then
                echo "$PATH_BLOCK" >> "$rc_file"
                printf "%b\n" "${GREEN}[✓] PATH added to $(basename "$rc_file")${RC}"
            else
                printf "%b\n" "${GREEN}[✓] PATH already configured in $(basename "$rc_file")${RC}"
            fi
        fi
    done
}

# ─── Step 6: Source and verify ────────────────────────────────────────────────
verify_setup() {
    printf "%b\n" "${CYAN}━━━ [6/6] Verification ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RC}"

    # Export into current session
    export ANTHROPIC_BASE_URL="$ZAI_BASE_URL"
    export ANTHROPIC_API_KEY="$API_KEY"
    export ANTHROPIC_DEFAULT_SONNET_MODEL="$SONNET_MODEL"
    export ANTHROPIC_DEFAULT_OPUS_MODEL="$OPUS_MODEL"
    export ANTHROPIC_DEFAULT_HAIKU_MODEL="$HAIKU_MODEL"
    export CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1

    # Source shell RC into current context (best-effort)
    SHELL_RC=$(detect_shell_rc)
    if [ -f "$SHELL_RC" ]; then
        # shellcheck disable=SC1090
        . "$SHELL_RC" 2>/dev/null || true
    fi

    # Verify critical exports
    ERRORS=0

    if [ -z "$ANTHROPIC_BASE_URL" ]; then
        printf "%b\n" "${RED}[✗] ANTHROPIC_BASE_URL not set${RC}"
        ERRORS=$((ERRORS + 1))
    else
        printf "%b\n" "${GREEN}[✓] ANTHROPIC_BASE_URL = $ANTHROPIC_BASE_URL${RC}"
    fi

    if [ -z "$ANTHROPIC_API_KEY" ]; then
        printf "%b\n" "${RED}[✗] ANTHROPIC_API_KEY not set${RC}"
        ERRORS=$((ERRORS + 1))
    else
        printf "%b\n" "${GREEN}[✓] ANTHROPIC_API_KEY = ****$(echo "$ANTHROPIC_API_KEY" | tail -c 5)${RC}"
    fi

    if ! command_exists claude; then
        printf "%b\n" "${RED}[✗] claude command not found in PATH${RC}"
        ERRORS=$((ERRORS + 1))
    else
        printf "%b\n" "${GREEN}[✓] claude CLI available — $(claude --version 2>/dev/null || echo 'installed')${RC}"
    fi

    if [ ! -f "$SETTINGS_FILE" ]; then
        printf "%b\n" "${RED}[✗] $SETTINGS_FILE not found${RC}"
        ERRORS=$((ERRORS + 1))
    else
        printf "%b\n" "${GREEN}[✓] $SETTINGS_FILE exists${RC}"
    fi

    if [ "$ERRORS" -gt 0 ]; then
        printf "%b\n" "${YELLOW}[~] $ERRORS issue(s) detected. Restart terminal and verify manually.${RC}"
    fi
}

# ─── Summary ─────────────────────────────────────────────────────────────────
print_summary() {
    echo ""
    printf "%b\n" "${CYAN}=================================================================${RC}"
    printf "%b\n" "${GREEN}  Claude Code + Z.AI GLM — Setup Complete!${RC}"
    printf "%b\n" "${CYAN}=================================================================${RC}"
    echo ""
    printf "%b\n" "${YELLOW}  Configuration:${RC}"
    printf "%b\n" "${CYAN}    Provider:     Z.AI (api.z.ai)${RC}"
    printf "%b\n" "${CYAN}    Sonnet Model: $SONNET_MODEL${RC}"
    printf "%b\n" "${CYAN}    Opus Model:   $OPUS_MODEL${RC}"
    printf "%b\n" "${CYAN}    Haiku Model:  $HAIKU_MODEL${RC}"
    echo ""
    printf "%b\n" "${YELLOW}  Files Modified:${RC}"
    printf "%b\n" "${CYAN}    $SETTINGS_FILE${RC}"
    for rc_file in $HOME/.zshrc $HOME/.bashrc; do
        if [ -f "$rc_file" ] && grep -q "Z.AI Claude Code" "$rc_file"; then
            printf "%b\n" "${CYAN}    $rc_file${RC}"
        fi
    done
    echo ""
    printf "%b\n" "${YELLOW}  Quick Start:${RC}"
    printf "%b\n" "${CYAN}    claude          — Start Claude Code with GLM models${RC}"
    printf "%b\n" "${CYAN}    claude --model  — Override model for this session${RC}"
    echo ""
    printf "%b\n" "${YELLOW}  Note: Restart your terminal if 'claude' command is not found.${RC}"
    printf "%b\n" "${CYAN}=================================================================${RC}"
}

# ─── Main Execution ──────────────────────────────────────────────────────────
get_api_key
create_settings
configure_shell
install_claude
persist_paths
verify_setup
print_summary
