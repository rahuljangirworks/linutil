#!/bin/sh -e

# Description: Install/update Herdr and bind it to RahulOS agent workflows.
# Rerunnable:  Yes - existing config is preserved and integrations are reinstalled safely.

. ../../common-script.sh

HERDR_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/herdr"
HERDR_CONFIG="$HERDR_CONFIG_DIR/config.toml"
RAHULOS_LAUNCHER="$HOME/.local/bin/rahulos-herdr"
RAHULOS_WORK="/home/rahul/.work"
export PATH="$HOME/.local/bin:$HOME/.npm-global/bin:$PATH"

ensureBasicTools() {
    missing=""
    for cmd in cat curl mkdir chmod printf sed awk; do
        if ! command -v "$cmd" > /dev/null 2>&1; then
            missing="$missing $cmd"
        fi
    done

    if [ -n "$missing" ]; then
        printf "%b\n" "${RED}Missing required commands:$missing${RC}"
        exit 1
    fi
}

installNodeAndNpm() {
    if command -v node > /dev/null 2>&1 && command -v npm > /dev/null 2>&1; then
        return 0
    fi

    printf "%b\n" "${YELLOW}Installing Node.js/npm for npm-based AI CLIs...${RC}"
    case "$PACKAGER" in
        pacman)
            "$ESCALATION_TOOL" pacman -S --needed --noconfirm nodejs npm
            ;;
        apt-get|nala)
            "$ESCALATION_TOOL" "$PACKAGER" update
            "$ESCALATION_TOOL" "$PACKAGER" install -y nodejs npm
            ;;
        dnf|yum)
            "$ESCALATION_TOOL" "$PACKAGER" install -y nodejs npm
            ;;
        zypper)
            "$ESCALATION_TOOL" zypper install -y nodejs npm
            ;;
        apk)
            "$ESCALATION_TOOL" apk add nodejs npm
            ;;
        xbps-install)
            "$ESCALATION_TOOL" xbps-install -Sy nodejs npm
            ;;
        eopkg)
            "$ESCALATION_TOOL" eopkg install -y nodejs npm
            ;;
        *)
            printf "%b\n" "${RED}Unsupported package manager for Node.js/npm: $PACKAGER${RC}"
            exit 1
            ;;
    esac
}

ensureNpmUserPrefix() {
    npm_prefix=$(npm config get prefix 2>/dev/null || printf "")

    case "$npm_prefix" in
        "$HOME"/*)
            ;;
        *)
            mkdir -p "$HOME/.npm-global"
            npm config set prefix "$HOME/.npm-global"
            export PATH="$HOME/.npm-global/bin:$PATH"
            printf "%b\n" "${GREEN}✓ npm global prefix set to $HOME/.npm-global${RC}"
            ;;
    esac
}

installHerdr() {
    if command -v herdr > /dev/null 2>&1; then
        printf "%b\n" "${GREEN}✓ Herdr found: $(herdr --version 2>/dev/null || printf 'installed')${RC}"
        printf "%b" "${YELLOW}Run 'herdr update' now? [y/N]: ${RC}"
        read -r update_choice
        case "$update_choice" in
            y|Y|yes|YES)
                herdr update || printf "%b\n" "${YELLOW}Herdr update did not complete. Continuing with installed Herdr.${RC}"
                ;;
            *)
                printf "%b\n" "${CYAN}Keeping the installed Herdr version.${RC}"
                ;;
        esac
        return 0
    fi

    printf "%b\n" "${YELLOW}Installing Herdr from the official installer...${RC}"
    curl -fsSL https://herdr.dev/install.sh | sh

    if ! command -v herdr > /dev/null 2>&1; then
        printf "%b\n" "${RED}Herdr installer finished, but 'herdr' is not on PATH.${RC}"
        printf "%b\n" "${CYAN}Restart the terminal or add ~/.local/bin to PATH, then rerun this setup.${RC}"
        exit 1
    fi

    printf "%b\n" "${GREEN}✓ Herdr installed: $(herdr --version)${RC}"
}

installGeminiCli() {
    installNodeAndNpm
    ensureNpmUserPrefix

    if command -v gemini > /dev/null 2>&1; then
        printf "%b\n" "${GREEN}✓ Gemini CLI found: $(gemini --version 2>/dev/null || printf 'installed')${RC}"
        printf "%b\n" "${YELLOW}Updating Gemini CLI with npm...${RC}"
    else
        printf "%b\n" "${YELLOW}Installing Gemini CLI with npm...${RC}"
    fi

    npm install -g @google/gemini-cli@latest
    printf "%b\n" "${GREEN}✓ Gemini CLI ready${RC}"
}

installAntigravityCli() {
    if command -v agy > /dev/null 2>&1; then
        printf "%b\n" "${GREEN}✓ Antigravity CLI found: $(agy --version 2>/dev/null || printf 'installed')${RC}"
        printf "%b\n" "${YELLOW}Updating Antigravity CLI with agy update...${RC}"
        agy update || printf "%b\n" "${YELLOW}agy update did not complete. Continuing with installed Antigravity CLI.${RC}"
        return 0
    fi

    printf "%b\n" "${YELLOW}Installing Antigravity CLI from the official Google installer...${RC}"
    curl -fsSL https://antigravity.google/cli/install.sh | bash

    if command -v agy > /dev/null 2>&1; then
        printf "%b\n" "${GREEN}✓ Antigravity CLI ready: $(agy --version 2>/dev/null || printf 'installed')${RC}"
    else
        printf "%b\n" "${YELLOW}Antigravity installer finished, but 'agy' is not on PATH yet.${RC}"
        printf "%b\n" "${CYAN}Restart the terminal or add ~/.local/bin to PATH, then run 'agy'.${RC}"
    fi
}

installAionUi() {
    if command -v aionui > /dev/null 2>&1 || command -v aion > /dev/null 2>&1; then
        printf "%b\n" "${GREEN}✓ AionUi/Aion CLI already found on PATH${RC}"
        return 0
    fi

    printf "%b" "${YELLOW}Install AionUi Linux headless runtime with the official installer? [Y/n]: ${RC}"
    read -r aion_choice
    case "${aion_choice:-Y}" in
        y|Y|yes|YES)
            curl -fsSL https://get.aionui.com | bash || {
                printf "%b\n" "${YELLOW}AionUi install did not complete. You can install the desktop build manually from https://aionui.com/download/.${RC}"
                return 0
            }
            ;;
        *)
            printf "%b\n" "${CYAN}Skipped AionUi install.${RC}"
            ;;
    esac
}

writeHerdrConfig() {
    mkdir -p "$HERDR_CONFIG_DIR"

    if [ -f "$HERDR_CONFIG" ]; then
        printf "%b\n" "${CYAN}Preserving existing Herdr config: $HERDR_CONFIG${RC}"
        return 0
    fi

    cat > "$HERDR_CONFIG" <<'EOF'
onboarding = false

[update]
channel = "stable"
version_check = true
manifest_check = true

[terminal]
new_cwd = "follow"

[session]
resume_agents_on_restore = true
EOF

    printf "%b\n" "${GREEN}✓ Created Herdr config: $HERDR_CONFIG${RC}"
}

writeRahulOSLauncher() {
    mkdir -p "$HOME/.local/bin"

    cat > "$RAHULOS_LAUNCHER" <<'EOF'
#!/bin/sh
set -e

cd /home/rahul/.work
exec herdr
EOF

    chmod +x "$RAHULOS_LAUNCHER"
    printf "%b\n" "${GREEN}✓ Created RahulOS Herdr launcher: $RAHULOS_LAUNCHER${RC}"
}

ensureIntegrationDirs() {
    [ -d "$HOME/.pi/agent/extensions" ] || mkdir -p "$HOME/.pi/agent/extensions"
    [ -d "${CLAUDE_CONFIG_DIR:-$HOME/.claude}" ] || mkdir -p "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
    [ -d "${CODEX_HOME:-$HOME/.codex}" ] || mkdir -p "${CODEX_HOME:-$HOME/.codex}"
    [ -d "${XDG_CONFIG_HOME:-$HOME/.config}/opencode/plugins" ] || mkdir -p "${XDG_CONFIG_HOME:-$HOME/.config}/opencode/plugins"
    [ -d "${XDG_CONFIG_HOME:-$HOME/.config}/kilo/plugin" ] || mkdir -p "${XDG_CONFIG_HOME:-$HOME/.config}/kilo/plugin"
    [ -d "$HOME/.hermes/plugins" ] || mkdir -p "$HOME/.hermes/plugins"
}

installIntegrationIfPresent() {
    agent_name="$1"
    command_name="$2"

    if ! command -v "$command_name" > /dev/null 2>&1; then
        printf "%b\n" "${YELLOW}Skipping $agent_name integration: '$command_name' not found on PATH.${RC}"
        return 0
    fi

    printf "%b\n" "${YELLOW}Installing Herdr integration: $agent_name${RC}"
    if herdr integration install "$agent_name"; then
        printf "%b\n" "${GREEN}✓ Installed Herdr integration: $agent_name${RC}"
    else
        printf "%b\n" "${YELLOW}Could not install $agent_name integration. Check config directory and rerun if needed.${RC}"
    fi
}

installHerdrIntegrations() {
    ensureIntegrationDirs
    installIntegrationIfPresent pi pi
    installIntegrationIfPresent claude claude
    installIntegrationIfPresent codex codex
    installIntegrationIfPresent opencode opencode
    installIntegrationIfPresent kilo kilo
    installIntegrationIfPresent hermes hermes

    printf "%b\n" "${CYAN}Gemini CLI, Antigravity CLI, AionUi, and qwen can run inside Herdr panes, but Herdr does not currently expose native integrations for all of them.${RC}"

    if herdr integration status > /tmp/rahulos-herdr-integration-status.txt 2>&1; then
        printf "%b\n" "${GREEN}✓ Herdr integration status:${RC}"
        sed 's/^/  /' /tmp/rahulos-herdr-integration-status.txt
    fi

    herdr server update-agent-manifests > /dev/null 2>&1 || true
}

installAgentSkill() {
    if ! command -v npx > /dev/null 2>&1; then
        printf "%b\n" "${YELLOW}Skipping Herdr agent skill install: npx not found.${RC}"
        return 0
    fi

    printf "%b" "${YELLOW}Install/update the global Herdr agent skill with npx? [Y/n]: ${RC}"
    read -r skill_choice
    case "${skill_choice:-Y}" in
        y|Y|yes|YES)
            if npx --yes skills add ogulcancelik/herdr --skill herdr -g; then
                printf "%b\n" "${GREEN}✓ Herdr agent skill installed globally.${RC}"
            else
                printf "%b\n" "${YELLOW}Herdr skill install did not complete. You can rerun later:${RC}"
                printf "%b\n" "${CYAN}  npx skills add ogulcancelik/herdr --skill herdr -g${RC}"
            fi
            ;;
        *)
            printf "%b\n" "${CYAN}Skipped Herdr agent skill install.${RC}"
            ;;
    esac
}

printAgentInventory() {
    printf "%b\n" "${GREEN}========================================${RC}"
    printf "%b\n" "${GREEN}  RahulOS Herdr Runtime${RC}"
    printf "%b\n" "${GREEN}========================================${RC}"
    printf "%b\n" "${CYAN}  Root workspace : $RAHULOS_WORK${RC}"
    printf "%b\n" "${CYAN}  Launcher       : $RAHULOS_LAUNCHER${RC}"
    printf "%b\n" "${CYAN}  Start          : rahulos-herdr${RC}"
    printf "%b\n" "${CYAN}  Manual start   : cd $RAHULOS_WORK && herdr${RC}"
    printf "%b\n" "${CYAN}  Detach         : Ctrl+b then q${RC}"
    printf "%b\n" "${CYAN}  Stop server    : herdr server stop${RC}"
    printf "%b\n" "${GREEN}----------------------------------------${RC}"
    printf "%b\n" "${CYAN}  Use these inside Herdr panes as needed:${RC}"

    for cmd in codex claude pi opencode kilo agy gemini qwen aion aionui; do
        if command -v "$cmd" > /dev/null 2>&1; then
            printf "%b\n" "${GREEN}    ✓ $cmd -> $(command -v "$cmd")${RC}"
        else
            printf "%b\n" "${YELLOW}    - $cmd not found${RC}"
        fi
    done

    printf "%b\n" "${GREEN}----------------------------------------${RC}"
    printf "%b\n" "${CYAN}  RahulOS rule:${RC}"
    printf "%b\n" "${CYAN}    Herdr owns panes and live status.${RC}"
    printf "%b\n" "${CYAN}    /home/rahul/.work owns durable brain truth.${RC}"
    printf "%b\n" "${CYAN}    Agents use Herdr pane control only when HERDR_ENV=1.${RC}"
    printf "%b\n" "${GREEN}========================================${RC}"
}

checkCurrentDirectoryWritable
checkEscalationTool
checkPackageManager 'nala apt-get dnf pacman zypper apk xbps-install eopkg'
ensureBasicTools
installHerdr
installGeminiCli
installAntigravityCli
installAionUi
writeHerdrConfig
writeRahulOSLauncher
installHerdrIntegrations
installAgentSkill
printAgentInventory
