#!/bin/sh -e

# Description: Install Claude Code & configure free-claude-code proxy for NVIDIA NIM Qwen3 Coder 480B
# Works on: Arch, Debian, Fedora, openSUSE, Void, Alpine, Solus

. ../common-script.sh

checkEnv

# ─── Globals ──────────────────────────────────────────────────────────────────
NPM_GLOBAL="$HOME/.npm-global"
PIPX_BIN="$HOME/.local/bin"
NIM_ROUTE="nvidia_nim/qwen/qwen3-coder-480b-a35b-instruct"
NIM_DISPLAY_NAME="NVIDIA NIM Qwen3 Coder 480B"

# ─── Header ──────────────────────────────────────────────────────────────────
clear
printf "%b\n" "${CYAN}=================================================================${RC}"
printf "%b\n" "${YELLOW}    Claude Code + NVIDIA NIM (Qwen3 Coder 480B) Setup            ${RC}"
printf "%b\n" "${CYAN}=================================================================${RC}"
printf "%b\n" "${GREEN}  This script installs Anthropic's Claude Code CLI and configures${RC}"
printf "%b\n" "${GREEN}  free-claude-code as a local proxy to query Qwen3 Coder 480B${RC}"
printf "%b\n" "${GREEN}  through NVIDIA NIM for free coding work.${RC}"
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
        printf "%b\n" "${YELLOW}[*] Claude Code already installed; updating to latest...${RC}"
        setup_npm_global
        npm install -g @anthropic-ai/claude-code@latest
        printf "%b\n" "${GREEN}[✓] Claude Code updated — $(claude --version 2>/dev/null || echo installed)${RC}"
    else
        printf "%b\n" "${YELLOW}[*] Installing @anthropic-ai/claude-code globally...${RC}"
        setup_npm_global
        npm install -g @anthropic-ai/claude-code@latest
        printf "%b\n" "${GREEN}[✓] Claude Code installed!${RC}"
    fi
}

# ─── Configure: Claude Code settings ─────────────────────────────────────────
configure_claude_settings() {
    # Avoid /doctor reporting "Auto-updates: disabled (config)" after setup.
    if command_exists node; then
        node <<'NODE'
const fs = require("fs");
const path = `${process.env.HOME}/.claude.json`;
let config = {};
if (fs.existsSync(path)) {
  try {
    config = JSON.parse(fs.readFileSync(path, "utf8"));
  } catch {
    config = {};
  }
}
config.installMethod = config.installMethod || "global";
config.autoUpdates = true;
fs.writeFileSync(path, JSON.stringify(config, null, 2) + "\n");
NODE
        printf "%b\n" "${GREEN}[✓] Claude Code auto-updates enabled in ~/.claude.json${RC}"
    fi
}

# ─── Dependency: uv (Python package manager) ─────────────────────────────────
install_uv() {
    printf "\n%b\n" "${CYAN}━━━ Installing uv Package Manager ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RC}"
    if command_exists uv; then
        printf "%b\n" "${GREEN}[✓] uv already installed${RC}"
    else
        printf "%b\n" "${YELLOW}[*] Installing uv...${RC}"
        curl -LsSf https://astral.sh/uv/install.sh | sh
        export PATH="$HOME/.local/bin:$PATH"
        printf "%b\n" "${GREEN}[✓] uv installed!${RC}"
    fi
}

# ─── Install: free-claude-code proxy ──────────────────────────────────────────
install_fcc() {
    printf "\n%b\n" "${CYAN}━━━ Installing free-claude-code Proxy ━━━━━━━━━━━━━━━━━━━━━━━━━${RC}"
    if command_exists fcc-server; then
        printf "%b\n" "${GREEN}[✓] free-claude-code already installed${RC}"
    else
        printf "%b\n" "${YELLOW}[*] Installing free-claude-code via uv...${RC}"
        export PATH="$HOME/.local/bin:$PATH"
        uv tool install --force git+https://github.com/Alishahryar1/free-claude-code.git
        printf "%b\n" "${GREEN}[✓] free-claude-code installed!${RC}"
    fi
}

# ─── Configure: NVIDIA API Key & free-claude-code ─────────────────────────────
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

    # Initialize free-claude-code config if not present
    if [ ! -f "$HOME/.fcc/.env" ]; then
        fcc-init 2>/dev/null || true
    fi

    # Write NVIDIA key and model into free-claude-code config
    if [ -f "$HOME/.fcc/.env" ]; then
        printf "%b\n" "${CYAN}[*] Configuring free-claude-code proxy...${RC}"
        sed -i "s|^NVIDIA_NIM_API_KEY=.*|NVIDIA_NIM_API_KEY=\"$API_KEY\"|" "$HOME/.fcc/.env"
        sed -i "s|^MODEL=.*|MODEL=\"$NIM_ROUTE\"|" "$HOME/.fcc/.env"
        sed -i 's|^FCC_OPEN_BROWSER=.*|FCC_OPEN_BROWSER=false|' "$HOME/.fcc/.env"
        printf "%b\n" "${GREEN}[✓] free-claude-code configured with $NIM_DISPLAY_NAME${RC}"
    fi

    # Create the wrapper script at ~/.local/bin/claude-nim
    mkdir -p "$HOME/.local/bin"
    printf "%b\n" "${CYAN}[*] Creating wrapper script at ~/.local/bin/claude-nim...${RC}"
    cat > "$HOME/.local/bin/claude-nim" <<'WRAPPER'
#!/bin/bash
# Wrapper script for Claude Code with NVIDIA NIM via free-claude-code proxy
# Uses: https://github.com/Alishahryar1/free-claude-code

PROXY_PORT=8082
PROXY_STARTED_BY_US=false

# Check if fcc-server is installed
if ! command -v fcc-server &>/dev/null; then
    echo "Error: fcc-server is not installed."
    echo "Install it with: uv tool install --force git+https://github.com/Alishahryar1/free-claude-code.git"
    exit 1
fi

# Check if free-claude-code proxy is already running
if ! curl -s -m 1 "http://localhost:${PROXY_PORT}/health" >/dev/null 2>&1; then
    echo "Starting free-claude-code proxy (NVIDIA NIM)..."
    env \
        -u NVIDIA_NIM_API_KEY \
        -u OPENROUTER_API_KEY \
        -u DEEPSEEK_API_KEY \
        -u KIMI_API_KEY \
        -u WAFER_API_KEY \
        -u OPENCODE_API_KEY \
        -u ZAI_API_KEY \
        -u FIREWORKS_API_KEY \
        FCC_OPEN_BROWSER=false fcc-server > /tmp/fcc-proxy.log 2>&1 &
    FCC_PID=$!
    PROXY_STARTED_BY_US=true

    # Wait for the proxy to boot (~2-4 seconds)
    for i in $(seq 1 15); do
        if curl -s -m 1 "http://localhost:${PROXY_PORT}/health" >/dev/null 2>&1; then
            break
        fi
        sleep 0.5
    done

    if ! curl -s -m 1 "http://localhost:${PROXY_PORT}/health" >/dev/null 2>&1; then
        echo "Error: free-claude-code proxy failed to start. Check /tmp/fcc-proxy.log"
        kill "$FCC_PID" 2>/dev/null
        exit 1
    fi
    echo "Proxy is running on port ${PROXY_PORT}."
fi

# Clear provider settings from other Claude setup scripts, then point Claude Code
# to the local NVIDIA NIM proxy. NVIDIA's Claude Code integration guide maps
# built-in Claude aliases to the NIM model so background tasks do not fall back
# to Anthropic model IDs.
unset ANTHROPIC_API_KEY
unset CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC
NIM_MODEL="anthropic/nvidia_nim/qwen/qwen3-coder-480b-a35b-instruct"
export ANTHROPIC_BASE_URL="http://localhost:${PROXY_PORT}"
export ANTHROPIC_AUTH_TOKEN="freecc"
export ANTHROPIC_CUSTOM_MODEL_OPTION="${NIM_MODEL}"
export ANTHROPIC_CUSTOM_MODEL_OPTION_NAME="NVIDIA NIM Qwen3 Coder 480B"
export ANTHROPIC_CUSTOM_MODEL_OPTION_DESCRIPTION="Qwen3 Coder 480B through local Free Claude Code proxy"
export ANTHROPIC_DEFAULT_HAIKU_MODEL="${NIM_MODEL}"
export ANTHROPIC_DEFAULT_OPUS_MODEL="${NIM_MODEL}"
export ANTHROPIC_DEFAULT_SONNET_MODEL="${NIM_MODEL}"
export CLAUDE_CODE_SUBAGENT_MODEL="${NIM_MODEL}"
export CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY="1"
export CLAUDE_CODE_AUTO_COMPACT_WINDOW="190000"

# Run Claude Code
echo "Launching Claude Code (NVIDIA NIM - Qwen3 Coder 480B)..."
claude "$@"

# Clean up proxy if we started it
if [ "$PROXY_STARTED_BY_US" = true ]; then
    echo "Stopping free-claude-code proxy..."
    kill "$FCC_PID" 2>/dev/null
fi
WRAPPER

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
    printf "%b\n" "${GREEN}  This will automatically start the free-claude-code proxy,${RC}"
    printf "%b\n" "${GREEN}  run Claude Code pointing to NVIDIA NIM Qwen3 Coder 480B,${RC}"
    printf "%b\n" "${GREEN}  and stop the proxy when you exit.${RC}"
    printf "%b\n" "${CYAN}=================================================================${RC}"
}

# ─── Main Execution ──────────────────────────────────────────────────────────
install_node
install_uv
install_claude
configure_claude_settings
install_fcc
configure_key_and_proxy
persist_paths
print_summary
