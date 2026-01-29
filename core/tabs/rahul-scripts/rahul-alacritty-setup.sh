#!/bin/sh -e

# Description: Setup Rahul's customized Alacritty configuration
# Repository: https://github.com/rahuljangirworks/dwm-rahul

. ../common-script.sh

installAlacritty() {
    if ! command_exists alacritty; then
        printf "%b\n" "${YELLOW}Installing Alacritty...${RC}"
        case "$PACKAGER" in
            pacman)
                "$ESCALATION_TOOL" "$PACKAGER" -S --needed --noconfirm alacritty
                ;;
            apk)
                "$ESCALATION_TOOL" "$PACKAGER" add alacritty
                ;;
            xbps-install)
                "$ESCALATION_TOOL" "$PACKAGER" -Sy alacritty
                ;;
            *)
                "$ESCALATION_TOOL" "$PACKAGER" install -y alacritty
                ;;
        esac
    else
        printf "%b\n" "${GREEN}Alacritty is already installed.${RC}"
    fi
}

setupAlacrittyConfig() {
    printf "%b\n" "${YELLOW}Setting up Rahul's Alacritty config...${RC}"
    
    # Backup existing config if it exists and no backup exists yet
    if [ -d "${HOME}/.config/alacritty" ] && [ ! -d "${HOME}/.config/alacritty-bak" ]; then
        printf "%b\n" "${YELLOW}Backing up existing Alacritty config...${RC}"
        cp -r "${HOME}/.config/alacritty" "${HOME}/.config/alacritty-bak"
    fi
    
    mkdir -p "${HOME}/.config/alacritty/"
    
    # Download config files from Rahul's dwm-rahul repo (avoids merge conflicts with upstream)
    printf "%b\n" "${CYAN}Downloading config from rahuljangirworks/dwm-rahul...${RC}"
    curl -sSLo "${HOME}/.config/alacritty/alacritty.toml" \
        "https://raw.githubusercontent.com/rahuljangirworks/dwm-rahul/main/config/alacritty/alacritty.toml"
    curl -sSLo "${HOME}/.config/alacritty/keybinds.toml" \
        "https://raw.githubusercontent.com/rahuljangirworks/dwm-rahul/main/config/alacritty/keybinds.toml"
    curl -sSLo "${HOME}/.config/alacritty/nordic.toml" \
        "https://raw.githubusercontent.com/rahuljangirworks/dwm-rahul/main/config/alacritty/nordic.toml"
    
    printf "%b\n" "${GREEN}Alacritty configuration installed!${RC}"
    printf "%b\n" "${CYAN}Config location: ~/.config/alacritty/${RC}"
}

# Main execution
checkEnv
checkEscalationTool
installAlacritty
setupAlacrittyConfig
