#!/bin/sh -e

# Description: Install and configure Tailscale VPN using the official Linux installer.
# Repository: https://tailscale.com
# Rerunnable: Yes - keeps existing login, starts service, and only runs tailscale up when needed.

. ../../common-script.sh

AUTH_TOKEN=""
TAILSCALE_HOSTNAME=""
READ_SECRET_VALUE=""

installTailscaleWithOfficialScript() {
    printf "%b\n" "${YELLOW}Installing Tailscale with official installer...${RC}"

    if [ "$(id -u)" = "0" ]; then
        curl -fsSL https://tailscale.com/install.sh | sh
    else
        curl -fsSL https://tailscale.com/install.sh | "$ESCALATION_TOOL" sh
    fi
}

installTailscaleWithPackageManager() {
    printf "%b\n" "${YELLOW}Official installer failed, trying package manager fallback...${RC}"

    case "$PACKAGER" in
        pacman)
            "$ESCALATION_TOOL" "$PACKAGER" -S --needed --noconfirm tailscale
            ;;
        apt-get|nala)
            "$ESCALATION_TOOL" "$PACKAGER" update
            "$ESCALATION_TOOL" "$PACKAGER" install -y tailscale
            ;;
        dnf|yum|zypper)
            "$ESCALATION_TOOL" "$PACKAGER" install -y tailscale
            ;;
        apk)
            "$ESCALATION_TOOL" "$PACKAGER" add tailscale
            ;;
        xbps-install)
            "$ESCALATION_TOOL" "$PACKAGER" -Sy tailscale
            ;;
        eopkg)
            "$ESCALATION_TOOL" "$PACKAGER" install -y tailscale
            ;;
        *)
            printf "%b\n" "${RED}✗ Unsupported package manager: $PACKAGER${RC}"
            return 1
            ;;
    esac
}

installTailscale() {
    if command_exists tailscale; then
        printf "%b\n" "${GREEN}✓ Tailscale already installed${RC}"
        return 0
    fi

    installTailscaleWithOfficialScript || installTailscaleWithPackageManager

    if command_exists tailscale; then
        printf "%b\n" "${GREEN}✓ Tailscale installed${RC}"
    else
        printf "%b\n" "${RED}✗ Tailscale installation failed${RC}"
        exit 1
    fi
}

enableTailscale() {
    if command_exists systemctl; then
        if systemctl is-active --quiet tailscaled 2>/dev/null; then
            printf "%b\n" "${GREEN}✓ Tailscale service already running${RC}"
            return 0
        fi

        printf "%b\n" "${YELLOW}Enabling and starting tailscaled...${RC}"
        "$ESCALATION_TOOL" systemctl enable --now tailscaled
        printf "%b\n" "${GREEN}✓ tailscaled enabled and started${RC}"
        return 0
    fi

    if command_exists rc-service; then
        printf "%b\n" "${YELLOW}Starting tailscaled with OpenRC...${RC}"
        "$ESCALATION_TOOL" rc-update add tailscale default 2>/dev/null || true
        "$ESCALATION_TOOL" rc-service tailscale start
        printf "%b\n" "${GREEN}✓ Tailscale service started${RC}"
        return 0
    fi

    if command_exists service; then
        printf "%b\n" "${YELLOW}Starting tailscaled with service...${RC}"
        "$ESCALATION_TOOL" service tailscaled start 2>/dev/null || "$ESCALATION_TOOL" service tailscale start
        printf "%b\n" "${GREEN}✓ Tailscale service started${RC}"
        return 0
    fi

    printf "%b\n" "${YELLOW}→ Could not detect service manager. Try manually: sudo tailscaled${RC}"
}

tailscaleBackendState() {
    tailscale status --json 2>/dev/null |
        sed -n 's/.*"BackendState"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p'
}

tailscaleIsRunning() {
    [ "$(tailscaleBackendState)" = "Running" ]
}

readSecret() {
    prompt="$1"
    secret=""

    printf "%b" "$prompt"
    if [ -t 0 ]; then
        old_stty=$(stty -g 2>/dev/null || true)
        if [ -n "$old_stty" ]; then
            stty -echo
        fi
        read -r secret
        if [ -n "$old_stty" ]; then
            stty "$old_stty"
            printf "\n"
        fi
    else
        read -r secret
    fi

    READ_SECRET_VALUE="$secret"
}

promptConfiguration() {
    printf "%b\n" "${CYAN}========================================${RC}"
    printf "%b\n" "${CYAN}Tailscale Configuration${RC}"
    printf "%b\n" "${CYAN}========================================${RC}"

    printf "%b" "${YELLOW}Device hostname in Tailscale [$(hostname)]: ${RC}"
    read -r TAILSCALE_HOSTNAME

    case "$TAILSCALE_HOSTNAME" in
        *[!A-Za-z0-9._-]*)
            printf "%b\n" "${RED}Hostname can only use letters, numbers, dot, underscore, and dash.${RC}"
            exit 1
            ;;
    esac

    printf "%b\n" "${CYAN}Authentication:${RC}"
    printf "%b\n" "${CYAN}  - Press Enter for browser login${RC}"
    printf "%b\n" "${CYAN}  - Paste an auth key for headless/server setup${RC}"
    readSecret "${YELLOW}Auth key (hidden, optional): ${RC}"
    AUTH_TOKEN="$READ_SECRET_VALUE"
}

runTailscaleUp() {
    if [ -n "$AUTH_TOKEN" ] && [ -n "$TAILSCALE_HOSTNAME" ]; then
        "$ESCALATION_TOOL" tailscale up --auth-key="$AUTH_TOKEN" --hostname="$TAILSCALE_HOSTNAME"
    elif [ -n "$AUTH_TOKEN" ]; then
        "$ESCALATION_TOOL" tailscale up --auth-key="$AUTH_TOKEN"
    elif [ -n "$TAILSCALE_HOSTNAME" ]; then
        "$ESCALATION_TOOL" tailscale up --hostname="$TAILSCALE_HOSTNAME"
    else
        "$ESCALATION_TOOL" tailscale up
    fi
}

configureTailscale() {
    if tailscaleIsRunning; then
        CURRENT_IP=$(tailscale ip -4 2>/dev/null || echo "unknown")
        CURRENT_HOST=$(tailscale status --self --json 2>/dev/null |
            sed -n 's/.*"HostName"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
        CURRENT_HOST="${CURRENT_HOST:-$(hostname)}"
        printf "%b\n" "${GREEN}✓ Tailscale already connected${RC}"
        printf "%b\n" "${CYAN}  IP: $CURRENT_IP | Hostname: $CURRENT_HOST${RC}"
        return 0
    fi

    promptConfiguration

    if [ -n "$AUTH_TOKEN" ]; then
        printf "%b\n" "${YELLOW}→ Authenticating with auth key...${RC}"
    else
        printf "%b\n" "${YELLOW}→ Starting browser login...${RC}"
    fi

    runTailscaleUp
    printf "%b\n" "${GREEN}✓ Tailscale configured${RC}"
}

printStatus() {
    printf "%b\n" "${GREEN}========================================${RC}"
    printf "%b\n" "${GREEN}Tailscale Setup Complete${RC}"
    printf "%b\n" "${GREEN}========================================${RC}"

    STATE=$(tailscaleBackendState)
    STATE="${STATE:-unknown}"
    printf "%b\n" "${CYAN}State: $STATE${RC}"

    if tailscale status >/dev/null 2>&1; then
        TS_IP=$(tailscale ip -4 2>/dev/null || echo "not connected")
        printf "%b\n" "${CYAN}Tailscale IP: $TS_IP${RC}"
    fi

    printf "%b\n" ""
    printf "%b\n" "${CYAN}Useful commands:${RC}"
    printf "%b\n" "${CYAN}  tailscale status       - Check connection status${RC}"
    printf "%b\n" "${CYAN}  tailscale ip           - Show Tailscale IP${RC}"
    printf "%b\n" "${CYAN}  tailscale ping <host>  - Test another device${RC}"
    printf "%b\n" "${CYAN}  tailscale logout       - Disconnect this device${RC}"
    printf "%b\n" "${GREEN}========================================${RC}"
}

checkEnv
checkEscalationTool
installTailscale
enableTailscale
configureTailscale
printStatus
