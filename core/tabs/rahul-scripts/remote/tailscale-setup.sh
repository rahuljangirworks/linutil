#!/bin/sh -e

# Description: Install and configure Tailscale VPN
# Repository: https://tailscale.com

. ../../common-script.sh

installTailscale() {
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
    
    printf "%b\n" "${GREEN}Tailscale installed successfully${RC}"
}

enableTailscale() {
    printf "%b\n" "${YELLOW}Enabling and starting Tailscale service...${RC}"
    
    "$ESCALATION_TOOL" systemctl enable --now tailscaled
    
    printf "%b\n" "${GREEN}Tailscale service enabled and started${RC}"
}

configureTailscale() {
    printf "%b\n" "${CYAN}========================================${RC}"
    printf "%b\n" "${CYAN}Tailscale Configuration${RC}"
    printf "%b\n" "${CYAN}========================================${RC}"
    
    # Ask for hostname
    printf "%b" "${YELLOW}Enter hostname for this device (press Enter for default): ${RC}"
    read -r TAILSCALE_HOSTNAME
    
    if [ -n "$TAILSCALE_HOSTNAME" ]; then
        printf "%b\n" "${YELLOW}Starting Tailscale with hostname: $TAILSCALE_HOSTNAME${RC}"
        "$ESCALATION_TOOL" tailscale up --hostname="$TAILSCALE_HOSTNAME"
    else
        printf "%b\n" "${YELLOW}Starting Tailscale with default hostname...${RC}"
        "$ESCALATION_TOOL" tailscale up
    fi
}

printInstructions() {
    printf "%b\n" "${GREEN}========================================${RC}"
    printf "%b\n" "${GREEN}Tailscale Setup Complete!${RC}"
    printf "%b\n" "${GREEN}========================================${RC}"
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
printInstructions
