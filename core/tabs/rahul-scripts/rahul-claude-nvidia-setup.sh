#!/bin/sh -e

# Description: Install Claude Code & configure LiteLLM proxy for free DeepSeek-V4-Pro search & reasoning
# Works on: Arch, Debian, Fedora, openSUSE, Void, Alpine, Solus

. ../common-script.sh

checkEnv

# ─── Globals ──────────────────────────────────────────────────────────────────
NPM_GLOBAL="$HOME/.npm-global"
PIPX_BIN="$HOME/.local/bin"

# ─── Header ──────────────────────────────────────────────────────────────────
clear
printf "%b\n" "${CYAN}=================================================================${RC}"
printf "%b\n" "${YELLOW}    Claude Code + NVIDIA NIM (DeepSeek-V4-Pro) Setup             ${RC}"
printf "%b\n" "${CYAN}=================================================================${RC}"
printf "%b\n" "${GREEN}  This script installs Anthropic's Claude Code CLI and configures${RC}"
printf "%b\n" "${GREEN}  LiteLLM as a translation proxy to query DeepSeek-V4-Pro via${RC}"
printf "%b\n" "${GREEN}  NVIDIA NIM for free search and reasoning.${RC}"
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

# ─── Install: Claude Code ─────────────────────────────────────────────────────
install_claude() {
    printf "\n%b\n" "${CYAN}━━━ Installing Claude Code ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RC}"
    if command_exists claude; then
        printf "%b\n" "${GREEN}[✓] Claude Code already installed${RC}"
    else
        printf "%b\n" "${YELLOW}[*] Installing @anthropic-ai/claude-code globally...${RC}"
        setup_npm_global
        npm install -g @anthropic-ai/claude-code
        printf "%b\n" "${GREEN}[✓] Claude Code installed!${RC}"
    fi
}

# ─── Install: LiteLLM ─────────────────────────────────────────────────────────
install_litellm() {
    printf "\n%b\n" "${CYAN}━━━ Installing LiteLLM Proxy ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RC}"
    if command_exists litellm; then
        printf "%b\n" "${GREEN}[✓] LiteLLM already installed${RC}"
    else
        printf "%b\n" "${YELLOW}[*] Installing LiteLLM via pipx...${RC}"
        export PATH="$PIPX_BIN:$PATH"
        pipx install 'litellm[proxy]'
        printf "%b\n" "${GREEN}[✓] LiteLLM installed!${RC}"
    fi
}

# ─── Configure: NVIDIA API Key & LiteLLM Config ────────────────────────────────
configure_key_and_proxy() {
    printf "\n%b\n" "${CYAN}━━━ API & Proxy Configuration ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RC}"
    
    # Prompt for key
    printf "%b\n" "${YELLOW}Enter your NVIDIA API Key (nvapi-...):${RC}"
    read -r API_KEY

    if [ -z "$API_KEY" ]; then
        printf "%b\n" "${RED}[✗] API Key cannot be empty. Skipping configuration.${RC}"
        return
    fi

    # Write key to shell RCs
    printf "%b\n" "${CYAN}[*] Saving NVIDIA_API_KEY to shell RC files...${RC}"
    for rc_file in "$HOME/.bashrc" "$HOME/.zshrc"; do
        if [ -f "$rc_file" ]; then
            # Clean old entries
            sed -i '/# NVIDIA NIM/d; /NVIDIA_API_KEY/d' "$rc_file"
            cat >> "$rc_file" <<EOF

# NVIDIA NIM API Key (managed by linutil)
export NVIDIA_API_KEY="$API_KEY"
EOF
        fi
    done
    export NVIDIA_API_KEY="$API_KEY"

    # Create config directory for LiteLLM
    mkdir -p "$HOME/.config/litellm"

    # Write config.yaml
    printf "%b\n" "${CYAN}[*] Writing LiteLLM configuration to ~/.config/litellm/config.yaml...${RC}"
    cat > "$HOME/.config/litellm/config.yaml" <<EOF
model_list:
  - model_name: deepseek-chat
    litellm_params:
      model: openai/deepseek-ai/deepseek-v4-pro
      api_base: https://integrate.api.nvidia.com/v1
      api_key: "os.environ/NVIDIA_API_KEY"
EOF

    # Create the wrapper script at ~/.local/bin/claude-nim
    mkdir -p "$HOME/.local/bin"
    printf "%b\n" "${CYAN}[*] Creating wrapper script at ~/.local/bin/claude-nim...${RC}"
    cat > "$HOME/.local/bin/claude-nim" <<'EOF'
#!/bin/bash
# Wrapper script for Claude Code with NVIDIA NIM DeepSeek-V4-Pro

if [ -z "$NVIDIA_API_KEY" ]; then
    echo "Error: NVIDIA_API_KEY environment variable is not set."
    echo "Please run the setup script or export it manually."
    exit 1
fi

PROXY_STARTED_BY_US=false

# Check if LiteLLM is already running on port 4000
if ! curl -s -m 1 http://localhost:4000/health >/dev/null 2>&1; then
    echo "Starting LiteLLM Translation Proxy..."
    # Start proxy in the background
    litellm --config "$HOME/.config/litellm/config.yaml" --port 4000 > /tmp/litellm-proxy.log 2>&1 &
    LITELLM_PID=$!
    PROXY_STARTED_BY_US=true

    # Wait for the proxy to boot
    for i in {1..20}; do
        if curl -s -m 1 http://localhost:4000/health >/dev/null 2>&1; then
            break
        fi
        sleep 0.5
    done

    if ! curl -s -m 1 http://localhost:4000/health >/dev/null 2>&1; then
        echo "Error: LiteLLM Proxy failed to start. Check /tmp/litellm-proxy.log"
        exit 1
    fi
    echo "LiteLLM Proxy is running."
fi

# Point Claude Code to the local proxy
export ANTHROPIC_BASE_URL="http://localhost:4000"
export ANTHROPIC_API_KEY="sk-12345"

# Run Claude Code
echo "Launching Claude Code (NVIDIA NIM - DeepSeek-V4-Pro)..."
claude --model deepseek-chat "$@"

# Clean up proxy if we started it
if [ "$PROXY_STARTED_BY_US" = true ]; then
    echo "Stopping LiteLLM Translation Proxy..."
    kill "$LITELLM_PID" 2>/dev/null
fi
EOF

    chmod +x "$HOME/.local/bin/claude-nim"
    printf "%b\n" "${GREEN}[✓] Wrapper script created and made executable${RC}"
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
}

# ─── Summary ─────────────────────────────────────────────────────────────────
print_summary() {
    echo ""
    printf "%b\n" "${CYAN}=================================================================${RC}"
    printf "%b\n" "${GREEN}  ✅  Claude Code + NVIDIA NIM Setup Complete!                   ${RC}"
    printf "%b\n" "${CYAN}=================================================================${RC}"
    echo ""
    printf "%b\n" "${YELLOW}  Quick Start:${RC}"
    printf "%b\n" "${CYAN}    1. Restart your terminal (or run 'source ~/.bashrc')${RC}"
    printf "%b\n" "${CYAN}    2. Run: claude-nim${RC}"
    echo ""
    printf "%b\n" "${GREEN}  This will automatically start LiteLLM, run Claude Code pointing${RC}"
    printf "%b\n" "${GREEN}  to NVIDIA NIM DeepSeek-V4-Pro, and stop LiteLLM when you exit.${RC}"
    printf "%b\n" "${CYAN}=================================================================${RC}"
}

# ─── Main Execution ──────────────────────────────────────────────────────────
install_node
install_python
install_claude
install_litellm
configure_key_and_proxy
persist_paths
print_summary
