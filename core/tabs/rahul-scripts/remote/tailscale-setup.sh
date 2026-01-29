#!/bin/sh -e

# Description: Install and configure Tailscale VPN
# Repository: https://tailscale.com
# Rerunnable: Yes - skips completed steps

. ../../common-script.sh

installTailscale() {
    # Check if already installed
    if command -v tailscale >/dev/null 2>&1; then
        printf "%b\n" "${GREEN}✓ Tailscale already installed${RC}"
        return 0
    fi
    
    printf "%b\n" "${YELLOW}Installing Tailscale...${RC}"
    
    case "$PACKAGER" in
        pacman)
            "$ESCALATION_TOOL" "$PACKAGER" -S --needed --noconfirm tailscale
            ;;
        apt-get|nala)
            # Add Tailscale's GPG key and repository for Debian/Ubuntu
            curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/jammy.noarmor.gpg | "$ESCALATION_TOOL" tee /usr/share/keyrings/tailscale-archive-keyring.gpg >/dev/null
            curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/jammy.tailscale-keyring.list | "$ESCALATION_TOOL" tee /etc/apt/sources.list.d/tailscale.list
            "$ESCALATION_TOOL" "$PACKAGER" update
            "$ESCALATION_TOOL" "$PACKAGER" install -y tailscale
            ;;
        dnf|yum)
            "$ESCALATION_TOOL" dnf config-manager --add-repo https://pkgs.tailscale.com/stable/fedora/tailscale.repo
            "$ESCALATION_TOOL" "$PACKAGER" install -y tailscale
            ;;
        zypper)
            "$ESCALATION_TOOL" zypper ar -g -r https://pkgs.tailscale.com/stable/opensuse/tumbleweed/tailscale.repo
            "$ESCALATION_TOOL" "$PACKAGER" --gpg-auto-import-keys refresh
            "$ESCALATION_TOOL" "$PACKAGER" install -y tailscale
            ;;
        *)
            # Fallback to official install script
            printf "%b\n" "${YELLOW}Using Tailscale's official install script...${RC}"
            curl -fsSL https://tailscale.com/install.sh | sh
            ;;
    esac
    
    printf "%b\n" "${GREEN}✓ Tailscale installed${RC}"
}

enableTailscale() {
    # Check if already running
    if systemctl is-active --quiet tailscaled 2>/dev/null; then
        printf "%b\n" "${GREEN}✓ Tailscale service already running${RC}"
        return 0
    fi
    
    printf "%b\n" "${YELLOW}Enabling and starting Tailscale service...${RC}"
    "$ESCALATION_TOOL" systemctl enable --now tailscaled
    printf "%b\n" "${GREEN}✓ Tailscale service enabled and started${RC}"
}

configureTailscale() {
    # Check if already connected
    if tailscale status >/dev/null 2>&1; then
        CURRENT_STATUS=$(tailscale status --json 2>/dev/null | grep -o '"BackendState":"[^"]*"' | cut -d'"' -f4)
        if [ "$CURRENT_STATUS" = "Running" ]; then
            CURRENT_IP=$(tailscale ip -4 2>/dev/null || echo "unknown")
            CURRENT_HOST=$(tailscale status --self --json 2>/dev/null | grep -o '"HostName":"[^"]*"' | cut -d'"' -f4 || hostname)
            printf "%b\n" "${GREEN}✓ Tailscale already connected${RC}"
            printf "%b\n" "${CYAN}  IP: $CURRENT_IP | Hostname: $CURRENT_HOST${RC}"
            return 0
        fi
    fi
    
    printf "%b\n" "${CYAN}========================================${RC}"
    printf "%b\n" "${CYAN}Tailscale Configuration${RC}"
    printf "%b\n" "${CYAN}========================================${RC}"
    
    # Ask for hostname
    printf "%b" "${YELLOW}Enter hostname for this device (press Enter for default): ${RC}"
    read -r TAILSCALE_HOSTNAME
    
    # Ask for auth token
    printf "%b\n" "${CYAN}Authentication methods:${RC}"
    printf "%b\n" "${CYAN}  1. Auth token (headless/automated setup)${RC}"
    printf "%b\n" "${CYAN}  2. Browser login (interactive)${RC}"
    printf "%b" "${YELLOW}Enter auth token (or press Enter for browser login): ${RC}"
    read -r AUTH_TOKEN
    
    # Build the command
    CMD_ARGS=""
    
    if [ -n "$TAILSCALE_HOSTNAME" ]; then
        CMD_ARGS="--hostname=$TAILSCALE_HOSTNAME"
    fi
    
    if [ -n "$AUTH_TOKEN" ]; then
        printf "%b\n" "${YELLOW}→ Authenticating with token...${RC}"
        # shellcheck disable=SC2086
        "$ESCALATION_TOOL" tailscale up --authkey="$AUTH_TOKEN" $CMD_ARGS
    else
        printf "%b\n" "${YELLOW}→ Opening browser for authentication...${RC}"
        # shellcheck disable=SC2086
        "$ESCALATION_TOOL" tailscale up $CMD_ARGS
    fi
    
    printf "%b\n" "${GREEN}✓ Tailscale configured${RC}"
}

printStatus() {
    printf "%b\n" "${GREEN}========================================${RC}"
    printf "%b\n" "${GREEN}Tailscale Setup Complete!${RC}"
    printf "%b\n" "${GREEN}========================================${RC}"
    
    # Show current status
    if tailscale status >/dev/null 2>&1; then
        TS_IP=$(tailscale ip -4 2>/dev/null || echo "not connected")
        printf "%b\n" "${CYAN}Tailscale IP: $TS_IP${RC}"
    fi
    
    printf "%b\n" "${CYAN}${RC}"
    printf "%b\n" "${CYAN}Useful commands:${RC}"
    printf "%b\n" "${CYAN}  tailscale status     - Check connection status${RC}"
    printf "%b\n" "${CYAN}  tailscale ip         - Show your Tailscale IP${RC}"
    printf "%b\n" "${CYAN}  tailscale ping <ip>  - Ping another device${RC}"
    printf "%b\n" "${CYAN}  tailscale logout     - Disconnect from Tailscale${RC}"
    printf "%b\n" "${GREEN}========================================${RC}"
}

# Main execution
checkEnv
checkEscalationTool
installTailscale
enableTailscale
configureTailscale
printStatus
