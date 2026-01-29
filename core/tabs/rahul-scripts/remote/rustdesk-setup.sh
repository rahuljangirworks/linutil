#!/bin/sh -e

# Description: Install and configure RustDesk remote desktop
# Repository: https://rustdesk.com
# Rerunnable: Yes - skips completed steps

. ../../common-script.sh

RUSTDESK_CONFIG_DIR="$HOME/.config/rustdesk"
RUSTDESK_CONFIG="$RUSTDESK_CONFIG_DIR/RustDesk2.toml"

installRustDesk() {
    # Check if already installed
    if command -v rustdesk >/dev/null 2>&1; then
        printf "%b\n" "${GREEN}✓ RustDesk already installed${RC}"
        return 0
    fi
    
    printf "%b\n" "${YELLOW}Installing RustDesk...${RC}"
    
    case "$PACKAGER" in
        pacman)
            # Try official repos first, fallback to AUR
            if "$ESCALATION_TOOL" "$PACKAGER" -S --needed --noconfirm rustdesk 2>/dev/null; then
                printf "%b\n" "${GREEN}✓ RustDesk installed from official repos${RC}"
            elif command -v yay >/dev/null 2>&1; then
                yay -S --needed --noconfirm rustdesk
                printf "%b\n" "${GREEN}✓ RustDesk installed from AUR${RC}"
            elif command -v paru >/dev/null 2>&1; then
                paru -S --needed --noconfirm rustdesk
                printf "%b\n" "${GREEN}✓ RustDesk installed from AUR${RC}"
            else
                printf "%b\n" "${YELLOW}AUR helper not found, installing via Flatpak...${RC}"
                installFlatpak
            fi
            ;;
        apt-get|nala)
            # Download latest deb from GitHub
            LATEST_URL=$(curl -s https://api.github.com/repos/rustdesk/rustdesk/releases/latest | grep "browser_download_url.*x86_64.*deb" | head -1 | cut -d '"' -f 4)
            if [ -n "$LATEST_URL" ]; then
                TEMP_DEB=$(mktemp --suffix=.deb)
                printf "%b\n" "${YELLOW}Downloading RustDesk...${RC}"
                curl -sL "$LATEST_URL" -o "$TEMP_DEB"
                "$ESCALATION_TOOL" apt-get update
                "$ESCALATION_TOOL" apt-get install -y "$TEMP_DEB"
                rm -f "$TEMP_DEB"
                printf "%b\n" "${GREEN}✓ RustDesk installed${RC}"
            else
                printf "%b\n" "${YELLOW}Could not fetch deb, trying Flatpak...${RC}"
                installFlatpak
            fi
            ;;
        dnf|yum)
            # Download latest rpm from GitHub
            LATEST_URL=$(curl -s https://api.github.com/repos/rustdesk/rustdesk/releases/latest | grep "browser_download_url.*x86_64.*rpm" | grep -v suse | head -1 | cut -d '"' -f 4)
            if [ -n "$LATEST_URL" ]; then
                TEMP_RPM=$(mktemp --suffix=.rpm)
                printf "%b\n" "${YELLOW}Downloading RustDesk...${RC}"
                curl -sL "$LATEST_URL" -o "$TEMP_RPM"
                "$ESCALATION_TOOL" "$PACKAGER" install -y "$TEMP_RPM"
                rm -f "$TEMP_RPM"
                printf "%b\n" "${GREEN}✓ RustDesk installed${RC}"
            else
                printf "%b\n" "${YELLOW}Could not fetch rpm, trying Flatpak...${RC}"
                installFlatpak
            fi
            ;;
        zypper)
            # Download latest suse rpm from GitHub
            LATEST_URL=$(curl -s https://api.github.com/repos/rustdesk/rustdesk/releases/latest | grep "browser_download_url.*suse.*rpm" | head -1 | cut -d '"' -f 4)
            if [ -n "$LATEST_URL" ]; then
                TEMP_RPM=$(mktemp --suffix=.rpm)
                printf "%b\n" "${YELLOW}Downloading RustDesk...${RC}"
                curl -sL "$LATEST_URL" -o "$TEMP_RPM"
                "$ESCALATION_TOOL" "$PACKAGER" install -y "$TEMP_RPM"
                rm -f "$TEMP_RPM"
                printf "%b\n" "${GREEN}✓ RustDesk installed${RC}"
            else
                printf "%b\n" "${YELLOW}Could not fetch rpm, trying Flatpak...${RC}"
                installFlatpak
            fi
            ;;
        *)
            installFlatpak
            ;;
    esac
}

installFlatpak() {
    if command -v flatpak >/dev/null 2>&1; then
        flatpak install -y flathub com.rustdesk.RustDesk
        printf "%b\n" "${GREEN}✓ RustDesk installed via Flatpak${RC}"
    else
        printf "%b\n" "${RED}✗ Flatpak not available. Please install RustDesk manually.${RC}"
        printf "%b\n" "${CYAN}Download from: https://github.com/rustdesk/rustdesk/releases${RC}"
        exit 1
    fi
}

enableService() {
    # Check if service exists
    if ! systemctl list-unit-files rustdesk.service >/dev/null 2>&1; then
        printf "%b\n" "${YELLOW}→ RustDesk service not found (may be Flatpak install)${RC}"
        return 0
    fi
    
    # Check if already running
    if systemctl is-active --quiet rustdesk 2>/dev/null; then
        printf "%b\n" "${GREEN}✓ RustDesk service already running${RC}"
        return 0
    fi
    
    printf "%b\n" "${YELLOW}Enabling RustDesk service...${RC}"
    "$ESCALATION_TOOL" systemctl enable --now rustdesk
    printf "%b\n" "${GREEN}✓ RustDesk service enabled and started${RC}"
}

configureServer() {
    printf "%b\n" "${CYAN}========================================${RC}"
    printf "%b\n" "${CYAN}RustDesk Server Configuration${RC}"
    printf "%b\n" "${CYAN}========================================${RC}"
    printf "%b\n" "${CYAN}You can use RustDesk's public servers (default)${RC}"
    printf "%b\n" "${CYAN}or configure your own self-hosted relay server.${RC}"
    printf "%b\n" ""
    
    printf "%b" "${YELLOW}Enter self-hosted relay server (or press Enter to skip): ${RC}"
    read -r RELAY_SERVER
    
    if [ -z "$RELAY_SERVER" ]; then
        printf "%b\n" "${GREEN}✓ Using default RustDesk public servers${RC}"
        return 0
    fi
    
    # Ask for public key
    printf "%b" "${YELLOW}Enter relay server public key: ${RC}"
    read -r PUBLIC_KEY
    
    if [ -z "$PUBLIC_KEY" ]; then
        printf "%b\n" "${RED}Public key is required for self-hosted server${RC}"
        return 1
    fi
    
    # Create config directory
    mkdir -p "$RUSTDESK_CONFIG_DIR"
    
    # Stop service if running to modify config
    if systemctl is-active --quiet rustdesk 2>/dev/null; then
        "$ESCALATION_TOOL" systemctl stop rustdesk
    fi
    
    # Check if config already has this server
    if [ -f "$RUSTDESK_CONFIG" ] && grep -q "rendezvous_server = '$RELAY_SERVER'" "$RUSTDESK_CONFIG" 2>/dev/null; then
        printf "%b\n" "${GREEN}✓ Server already configured${RC}"
    else
        # Update or create config
        if [ -f "$RUSTDESK_CONFIG" ]; then
            # Backup existing config
            cp "$RUSTDESK_CONFIG" "$RUSTDESK_CONFIG.bak"
        fi
        
        # Create/update config with relay server
        cat > "$RUSTDESK_CONFIG" << EOF
rendezvous_server = '$RELAY_SERVER'
nat_type = 1
serial = 0

[options]
custom-rendezvous-server = '$RELAY_SERVER'
relay-server = '$RELAY_SERVER'
key = '$PUBLIC_KEY'
EOF
        printf "%b\n" "${GREEN}✓ Configured relay server: $RELAY_SERVER${RC}"
    fi
    
    # Restart service if it was running
    if systemctl list-unit-files rustdesk.service >/dev/null 2>&1; then
        "$ESCALATION_TOOL" systemctl start rustdesk 2>/dev/null || true
    fi
}

printStatus() {
    printf "%b\n" "${GREEN}========================================${RC}"
    printf "%b\n" "${GREEN}RustDesk Setup Complete!${RC}"
    printf "%b\n" "${GREEN}========================================${RC}"
    
    # Try to get RustDesk ID
    if command -v rustdesk >/dev/null 2>&1; then
        RUSTDESK_ID=$(rustdesk --get-id 2>/dev/null || echo "Run 'rustdesk' to see your ID")
        printf "%b\n" "${CYAN}Your RustDesk ID: $RUSTDESK_ID${RC}"
    fi
    
    printf "%b\n" "${CYAN}${RC}"
    printf "%b\n" "${CYAN}To start RustDesk GUI: rustdesk${RC}"
    printf "%b\n" "${CYAN}To get your ID: rustdesk --get-id${RC}"
    printf "%b\n" "${CYAN}Config file: $RUSTDESK_CONFIG${RC}"
    printf "%b\n" "${GREEN}========================================${RC}"
}

# Main execution
checkEnv
checkEscalationTool
installRustDesk
enableService
configureServer
printStatus
