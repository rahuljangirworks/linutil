#!/bin/sh -e

# Description: Setup Rahul's customized Rofi configuration
# Repository: https://github.com/rahuljangirworks/dwm-rahul

. ../common-script.sh

installRofi() {
    if ! command_exists rofi; then
        printf "%b\n" "${YELLOW}Installing Rofi...${RC}"
        case "$PACKAGER" in
            pacman)
                "$ESCALATION_TOOL" "$PACKAGER" -S --needed --noconfirm rofi
                ;;
            apk)
                "$ESCALATION_TOOL" "$PACKAGER" add rofi
                ;;
            xbps-install)
                "$ESCALATION_TOOL" "$PACKAGER" -Sy rofi
                ;;
            *)
                "$ESCALATION_TOOL" "$PACKAGER" install -y rofi
                ;;
        esac
    else
        printf "%b\n" "${GREEN}Rofi is already installed.${RC}"
    fi
}

setupRofiConfig() {
    printf "%b\n" "${YELLOW}Setting up Rahul's Rofi config...${RC}"
    
    # Backup existing config if it exists and no backup exists yet
    if [ -d "$HOME/.config/rofi" ] && [ ! -d "$HOME/.config/rofi-bak" ]; then
        printf "%b\n" "${YELLOW}Backing up existing Rofi config...${RC}"
        cp -r "$HOME/.config/rofi" "$HOME/.config/rofi-bak"
    fi
    
    mkdir -p "$HOME/.config/rofi"
    mkdir -p "$HOME/.config/rofi/themes"
    
    # Download config files from Rahul's dwm-rahul repo (avoids merge conflicts with upstream)
    printf "%b\n" "${CYAN}Downloading config from rahuljangirworks/dwm-rahul...${RC}"
    
    # Main config files
    curl -sSLo "$HOME/.config/rofi/config.rasi" \
        "https://raw.githubusercontent.com/rahuljangirworks/dwm-rahul/main/config/rofi/config.rasi"
    curl -sSLo "$HOME/.config/rofi/powermenu.sh" \
        "https://raw.githubusercontent.com/rahuljangirworks/dwm-rahul/main/config/rofi/powermenu.sh"
    chmod +x "$HOME/.config/rofi/powermenu.sh"
    
    # Theme files
    curl -sSLo "$HOME/.config/rofi/themes/nord.rasi" \
        "https://raw.githubusercontent.com/rahuljangirworks/dwm-rahul/main/config/rofi/themes/nord.rasi"
    curl -sSLo "$HOME/.config/rofi/themes/sidetab-nord.rasi" \
        "https://raw.githubusercontent.com/rahuljangirworks/dwm-rahul/main/config/rofi/themes/sidetab-nord.rasi"
    curl -sSLo "$HOME/.config/rofi/themes/powermenu.rasi" \
        "https://raw.githubusercontent.com/rahuljangirworks/dwm-rahul/main/config/rofi/themes/powermenu.rasi"
    
    printf "%b\n" "${GREEN}Rofi configuration installed!${RC}"
    printf "%b\n" "${CYAN}Config location: ~/.config/rofi/${RC}"
}

# Main execution
checkEnv
checkEscalationTool
installRofi
setupRofiConfig
