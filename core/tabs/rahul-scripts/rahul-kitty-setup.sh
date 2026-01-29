#!/bin/sh -e

# Description: Setup Rahul's customized Kitty configuration
# Repository: https://github.com/rahuljangirworks/dwm-rahul

. ../common-script.sh

installKitty() {
    if ! command_exists kitty; then
        printf "%b\n" "${YELLOW}Installing Kitty...${RC}"
        case "$PACKAGER" in
            pacman)
                "$ESCALATION_TOOL" "$PACKAGER" -S --needed --noconfirm kitty
                ;;
            apk)
                "$ESCALATION_TOOL" "$PACKAGER" add kitty
                ;;
            xbps-install)
                "$ESCALATION_TOOL" "$PACKAGER" -Sy kitty
                ;;
            *)
                "$ESCALATION_TOOL" "$PACKAGER" install -y kitty
                ;;
        esac
    else
        printf "%b\n" "${GREEN}Kitty is already installed.${RC}"
    fi
}

setupKittyConfig() {
    printf "%b\n" "${YELLOW}Setting up Rahul's Kitty config...${RC}"
    
    # Backup existing config if it exists and no backup exists yet
    if [ -d "${HOME}/.config/kitty" ] && [ ! -d "${HOME}/.config/kitty-bak" ]; then
        printf "%b\n" "${YELLOW}Backing up existing Kitty config...${RC}"
        cp -r "${HOME}/.config/kitty" "${HOME}/.config/kitty-bak"
    fi
    
    mkdir -p "${HOME}/.config/kitty/"
    
    # Download config files from Rahul's dwm-rahul repo (avoids merge conflicts with upstream)
    printf "%b\n" "${CYAN}Downloading config from rahuljangirworks/dwm-rahul...${RC}"
    curl -sSLo "${HOME}/.config/kitty/kitty.conf" \
        "https://raw.githubusercontent.com/rahuljangirworks/dwm-rahul/main/config/kitty/kitty.conf"
    curl -sSLo "${HOME}/.config/kitty/nord.conf" \
        "https://raw.githubusercontent.com/rahuljangirworks/dwm-rahul/main/config/kitty/nord.conf"
    
    printf "%b\n" "${GREEN}Kitty configuration installed!${RC}"
    printf "%b\n" "${CYAN}Config location: ~/.config/kitty/${RC}"
}

# Main execution
checkEnv
checkEscalationTool
installKitty
setupKittyConfig
