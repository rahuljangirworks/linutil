#!/bin/sh -e

# Description: Install & configure Rahul's AI Terminal Agent Stack
# Agents: Qwen Code CLI, Gemini CLI, Kilo Code, Aider, Cline
# Works on: Arch, Debian, Fedora, openSUSE, Void, Alpine, Solus

. ../common-script.sh

checkEnv

# ─── Globals ──────────────────────────────────────────────────────────────────
NPM_GLOBAL="$HOME/.npm-global"
PIPX_BIN="$HOME/.local/bin"

# ─── Header ──────────────────────────────────────────────────────────────────
clear
printf "%b\n" "${CYAN}=================================================================${RC}"
printf "%b\n" "${YELLOW}    Rahul's AI Terminal Agent Stack — Full Installer              ${RC}"
printf "%b\n" "${CYAN}=================================================================${RC}"
printf "%b\n" "${GREEN}  [1] Qwen Code CLI   — Primary free agent (1000 req/day)${RC}"
printf "%b\n" "${GREEN}  [2] Gemini CLI      — Google's 1M context agent${RC}"
printf "%b\n" "${GREEN}  [3] Kilo Code CLI   — BYOM model-agnostic agent${RC}"
printf "%b\n" "${GREEN}  [4] Aider           — Git-native pair programmer${RC}"
printf "%b\n" "${GREEN}  [5] Cline CLI       — Agentic MCP-powered agent${RC}"
printf "%b\n" "${CYAN}=================================================================${RC}"
echo ""

# ─── Dependency: Node.js & npm ────────────────────────────────────────────────
install_node() {
    if command_exists node && command_exists npm; then
        printf "%b\n" "${GREEN}[✓] Node.js & npm already installed${RC}"
        return
    fi

    printf "%b\n" "${YELLOW}[*] Installing Node.js & npm...${RC}"
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
            printf "%b\n" "${RED}[✗] Cannot auto-install Node.js. Please install manually.${RC}"
            exit 1
            ;;
    esac
    printf "%b\n" "${GREEN}[✓] Node.js & npm installed${RC}"
}

# ─── Dependency: Python3 & pipx ───────────────────────────────────────────────
install_python() {
    if command_exists python3; then
        printf "%b\n" "${GREEN}[✓] Python3 already installed${RC}"
    else
        printf "%b\n" "${YELLOW}[*] Installing Python3...${RC}"
        case "$PACKAGER" in
            pacman)
                "$ESCALATION_TOOL" "$PACKAGER" -S --needed --noconfirm python python-pip
                ;;
            apk)
                "$ESCALATION_TOOL" "$PACKAGER" add python3 py3-pip
                ;;
            xbps-install)
                "$ESCALATION_TOOL" "$PACKAGER" -Sy python3 python3-pip
                ;;
            nala|apt-get|apt)
                "$ESCALATION_TOOL" apt-get update
                "$ESCALATION_TOOL" apt-get install -y python3 python3-pip python3-venv
                ;;
            dnf|zypper|eopkg)
                "$ESCALATION_TOOL" "$PACKAGER" install -y python3 python3-pip
                ;;
            *)
                printf "%b\n" "${RED}[✗] Cannot auto-install Python3. Please install manually.${RC}"
                exit 1
                ;;
        esac
        printf "%b\n" "${GREEN}[✓] Python3 installed${RC}"
    fi

    # Install pipx for isolated Python tool installs
    if command_exists pipx; then
        printf "%b\n" "${GREEN}[✓] pipx already installed${RC}"
    else
        printf "%b\n" "${YELLOW}[*] Installing pipx...${RC}"
        case "$PACKAGER" in
            pacman)
                "$ESCALATION_TOOL" "$PACKAGER" -S --needed --noconfirm python-pipx
                ;;
            nala|apt-get|apt)
                "$ESCALATION_TOOL" apt-get install -y pipx
                ;;
            dnf)
                "$ESCALATION_TOOL" "$PACKAGER" install -y pipx
                ;;
            *)
                python3 -m pip install --user pipx
                ;;
        esac
        # Ensure pipx bin path exists
        python3 -m pipx ensurepath 2>/dev/null || true
        export PATH="$PIPX_BIN:$PATH"
        printf "%b\n" "${GREEN}[✓] pipx installed${RC}"
    fi
}

# ─── npm global setup (no sudo needed) ────────────────────────────────────────
setup_npm_global() {
    if [ "$(id -u)" != "0" ]; then
        if [ ! -d "$NPM_GLOBAL" ]; then
            mkdir -p "$NPM_GLOBAL"
            npm config set prefix "$NPM_GLOBAL"
        fi
        # Ensure bin dir exists
        mkdir -p "$NPM_GLOBAL/bin"
        # Export to current session IMMEDIATELY
        case ":$PATH:" in
            *:"$NPM_GLOBAL/bin":*)
                ;; # Already in PATH
            *)
                export PATH="$NPM_GLOBAL/bin:$PATH"
                ;;
        esac
    fi
}

# ─── Install: Qwen Code CLI ──────────────────────────────────────────────────
install_qwen() {
    printf "\n%b\n" "${CYAN}━━━ [1/5] Qwen Code CLI ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RC}"
    if command_exists qwen; then
        printf "%b\n" "${GREEN}[✓] Qwen Code CLI already installed — $(qwen --version 2>/dev/null || echo 'installed')${RC}"
    else
        printf "%b\n" "${YELLOW}[*] Installing Qwen Code CLI...${RC}"
        setup_npm_global
        npm install -g @qwen-code/qwen-code
        printf "%b\n" "${GREEN}[✓] Qwen Code CLI installed! Run: qwen${RC}"
    fi
}

# ─── Install: Gemini CLI ─────────────────────────────────────────────────────
install_gemini() {
    printf "\n%b\n" "${CYAN}━━━ [2/5] Gemini CLI ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RC}"
    if command_exists gemini; then
        printf "%b\n" "${GREEN}[✓] Gemini CLI already installed — $(gemini --version 2>/dev/null || echo 'installed')${RC}"
    else
        printf "%b\n" "${YELLOW}[*] Installing Gemini CLI...${RC}"
        setup_npm_global
        npm install -g @google/gemini-cli
        printf "%b\n" "${GREEN}[✓] Gemini CLI installed! Run: gemini${RC}"
    fi
}

# ─── Install: Kilo Code CLI ──────────────────────────────────────────────────
install_kilo() {
    printf "\n%b\n" "${CYAN}━━━ [3/5] Kilo Code CLI ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RC}"
    if command_exists kilo; then
        printf "%b\n" "${GREEN}[✓] Kilo Code CLI already installed — $(kilo --version 2>/dev/null || echo 'installed')${RC}"
    else
        printf "%b\n" "${YELLOW}[*] Installing Kilo Code CLI...${RC}"
        setup_npm_global
        npm install -g @kilocode/cli
        printf "%b\n" "${GREEN}[✓] Kilo Code CLI installed! Run: kilo${RC}"
    fi
}

# ─── Install: Aider ──────────────────────────────────────────────────────────
install_aider() {
    printf "\n%b\n" "${CYAN}━━━ [4/5] Aider (Git-native AI pair programmer) ━━━━━━━━━━━━━━━${RC}"
    if command_exists aider; then
        printf "%b\n" "${GREEN}[✓] Aider already installed — $(aider --version 2>/dev/null || echo 'installed')${RC}"
    else
        printf "%b\n" "${YELLOW}[*] Installing Aider via pipx...${RC}"
        export PATH="$PIPX_BIN:$PATH"
        pipx install aider-chat
        printf "%b\n" "${GREEN}[✓] Aider installed! Run: aider${RC}"
    fi
}

# ─── Install: Cline CLI ──────────────────────────────────────────────────────
install_cline() {
    printf "\n%b\n" "${CYAN}━━━ [5/5] Cline CLI ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RC}"
    if command_exists cline; then
        printf "%b\n" "${GREEN}[✓] Cline CLI already installed — $(cline --version 2>/dev/null || echo 'installed')${RC}"
    else
        printf "%b\n" "${YELLOW}[*] Installing Cline CLI...${RC}"
        setup_npm_global
        npm install -g cline
        printf "%b\n" "${GREEN}[✓] Cline CLI installed! Run: cline${RC}"
    fi
}

# ─── Configure AgentRouter API (shared by all BYOM agents) ────────────────────
configure_api() {
    printf "\n%b\n" "${CYAN}━━━ API Configuration ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RC}"
    printf "%b\n" "${YELLOW}Configure AgentRouter API for BYOM agents? (Qwen/Kilo/Aider/Cline)${RC}"
    printf "%b\n" "${YELLOW}This sets OPENAI_API_KEY, OPENAI_BASE_URL, OPENAI_MODEL globally.${RC}"
    printf "%b " "${CYAN}Proceed? [y/N]:${RC}"
    read -r CONFIGURE_API

    case "$CONFIGURE_API" in
        y|Y|yes|YES)
            printf "%b\n" "${YELLOW}Enter your AgentRouter API Key (sk-...):${RC}"
            read -r API_KEY

            if [ -z "$API_KEY" ]; then
                printf "%b\n" "${RED}[✗] API Key is required! Skipping API config.${RC}"
                return
            fi

            printf "%b\n" "${CYAN}[*] Validating API Key with AgentRouter...${RC}"
            RESPONSE=$(curl -s https://agentrouter.org/v1/models -H "Authorization: Bearer $API_KEY" 2>/dev/null || echo "connection_error")

            if echo "$RESPONSE" | grep -q "connection_error"; then
                printf "%b\n" "${YELLOW}[~] Could not reach AgentRouter. Key saved anyway — verify manually.${RC}"
            elif echo "$RESPONSE" | grep -q "unauthorized_client_error"; then
                printf "%b\n" "${YELLOW}[~] Key accepted (AgentRouter blocks /models — this is normal)${RC}"
            elif echo "$RESPONSE" | grep -q "invalid\|not found\|token"; then
                printf "%b\n" "${RED}[✗] Invalid API Key! Verify at agentrouter.org/console/token${RC}"
                return
            else
                printf "%b\n" "${GREEN}[✓] API Key validated successfully!${RC}"
            fi

            # Global system config via /etc/profile.d/
            printf "%b\n" "${CYAN}[*] Writing /etc/profile.d/agentrouter.sh...${RC}"
            TMP_CONF=$(mktemp)
            cat > "$TMP_CONF" <<EOF
# AgentRouter — Global AI Agent Config (managed by linutil)
export OPENAI_API_KEY="$API_KEY"
export OPENAI_BASE_URL="https://agentrouter.org/v1"
export OPENAI_MODEL="deepseek-v3.2"
EOF

            "$ESCALATION_TOOL" mv "$TMP_CONF" /etc/profile.d/agentrouter.sh
            "$ESCALATION_TOOL" chmod 644 /etc/profile.d/agentrouter.sh

            # Shell RC fallback for non-login shells
            printf "%b\n" "${CYAN}[*] Adding fallback to shell RC files...${RC}"
            for rc_file in "$HOME/.bashrc" "$HOME/.zshrc"; do
                if [ -f "$rc_file" ]; then
                    # Clean old entries
                    sed -i '/# AgentRouter/d; /OPENAI_API_KEY/d; /OPENAI_BASE_URL/d; /OPENAI_MODEL/d' "$rc_file"
                    cat >> "$rc_file" <<EOF

# AgentRouter — AI Agent Config (managed by linutil)
export OPENAI_API_KEY="$API_KEY"
export OPENAI_BASE_URL="https://agentrouter.org/v1"
export OPENAI_MODEL="deepseek-v3.2"
EOF
                fi
            done

            # Source into current session
            export OPENAI_API_KEY="$API_KEY"
            export OPENAI_BASE_URL="https://agentrouter.org/v1"
            export OPENAI_MODEL="deepseek-v3.2"

            printf "%b\n" "${GREEN}[✓] AgentRouter API configured globally (model: deepseek-v3.2)${RC}"
            ;;
        *)
            printf "%b\n" "${YELLOW}[~] Skipping API configuration.${RC}"
            ;;
    esac
}

# ─── Ensure PATH persistence ─────────────────────────────────────────────────
persist_paths() {
    printf "\n%b\n" "${CYAN}━━━ PATH Configuration ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RC}"

    PATH_BLOCK="
# AI Agent Tools PATH (managed by linutil)
export PATH=\"\$HOME/.npm-global/bin:\$HOME/.local/bin:\$PATH\""

    # User-level RC files
    for rc_file in "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.profile" "$HOME/.bash_profile"; do
        if [ -f "$rc_file" ]; then
            if ! grep -q "AI Agent Tools PATH" "$rc_file"; then
                echo "$PATH_BLOCK" >> "$rc_file"
                printf "%b\n" "${GREEN}[✓] PATH added to $(basename "$rc_file")${RC}"
            else
                printf "%b\n" "${GREEN}[✓] PATH already configured in $(basename "$rc_file")${RC}"
            fi
        fi
    done

    # System-wide fallback via /etc/profile.d/
    if [ -d /etc/profile.d ]; then
        SYS_PATH_FILE="/etc/profile.d/ai-agents-path.sh"
        if [ ! -f "$SYS_PATH_FILE" ]; then
            printf "%b\n" "${CYAN}[*] Creating system-wide PATH fallback...${RC}"
            TMP_SYS=$(mktemp)
            cat > "$TMP_SYS" <<'EOF'
# AI Agent Tools PATH — system-wide (managed by linutil)
case ":$PATH:" in
    *:"$HOME/.npm-global/bin":*) ;;
    *) export PATH="$HOME/.npm-global/bin:$PATH" ;;
esac
case ":$PATH:" in
    *:"$HOME/.local/bin":*) ;;
    *) export PATH="$HOME/.local/bin:$PATH" ;;
esac
EOF
            "$ESCALATION_TOOL" mv "$TMP_SYS" "$SYS_PATH_FILE"
            "$ESCALATION_TOOL" chmod 644 "$SYS_PATH_FILE"
            printf "%b\n" "${GREEN}[✓] System-wide PATH fallback created${RC}"
        else
            printf "%b\n" "${GREEN}[✓] System-wide PATH already configured${RC}"
        fi
    fi
}

# ─── Summary ─────────────────────────────────────────────────────────────────
print_summary() {
    echo ""
    printf "%b\n" "${CYAN}=================================================================${RC}"
    printf "%b\n" "${GREEN}  ✅  AI Terminal Agent Stack — Installation Complete!           ${RC}"
    printf "%b\n" "${CYAN}=================================================================${RC}"
    echo ""
    printf "%b\n" "${YELLOW}  Installed Agents:${RC}"

    # Helper to check if command exists OR binary exists in npm-global
    check_agent() {
        _cmd="$1"
        _desc="$2"
        if command_exists "$_cmd"; then
            printf "%b\n" "${GREEN}    ✓ $_cmd        — $_desc${RC}"
        elif [ -x "$NPM_GLOBAL/bin/$_cmd" ]; then
            printf "%b\n" "${YELLOW}    ⚠ $_cmd        — $_desc (PATH not set — restart terminal)${RC}"
            PATH_WARN=1
        else
            printf "%b\n" "${RED}    ✗ $_cmd        — not found (re-run script)${RC}"
            PATH_WARN=1
        fi
    }

    PATH_WARN=0
    check_agent "qwen" "Qwen Code CLI (1000 free req/day)"
    check_agent "gemini" "Gemini CLI (1M context, free tier)"
    check_agent "kilo" "Kilo Code CLI (500+ models, BYOM)"
    check_agent "aider" "Aider (git-native, BYOK)"
    check_agent "cline" "Cline CLI (agentic, MCP)"

    echo ""
    printf "%b\n" "${YELLOW}  Quick Start:${RC}"
    printf "%b\n" "${CYAN}    qwen          — Start Qwen Code (primary free agent)${RC}"
    printf "%b\n" "${CYAN}    gemini        — Start Gemini (large context tasks)${RC}"
    printf "%b\n" "${CYAN}    kilo          — Start Kilo Code (switch models freely)${RC}"
    printf "%b\n" "${CYAN}    aider         — Start Aider (git-native pair coding)${RC}"
    printf "%b\n" "${CYAN}    cline         — Start Cline (agentic MCP workflows)${RC}"
    echo ""

    if [ "$PATH_WARN" = "1" ]; then
        printf "%b\n" "${YELLOW}  ⚠  Some agents need PATH update. Do ONE of these:${RC}"
        printf "%b\n" "${YELLOW}     1. Restart your terminal (recommended)${RC}"
        printf "%b\n" "${YELLOW}     2. Run: source ~/.bashrc  (or ~/.zshrc)${RC}"
        printf "%b\n" "${YELLOW}     3. Run: export PATH=\"\$HOME/.npm-global/bin:\$PATH\"${RC}"
    else
        printf "%b\n" "${GREEN}  ✅  All agents are ready to use!${RC}"
    fi

    printf "%b\n" "${CYAN}=================================================================${RC}"
}

# ─── Main Execution ──────────────────────────────────────────────────────────
install_node
install_python
install_qwen
install_gemini
install_kilo
install_aider
install_cline
configure_api
persist_paths
print_summary
