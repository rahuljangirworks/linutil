#!/bin/sh -e

# Description: Setup Rahul's customized DWM environment
# Repository: https://github.com/rahuljangirworks/dwm-rahul

. ../common-script.sh

DWM_DIR="$HOME/.local/share/dwm-rahul"

setupXorg() {
    printf "%b\n" "${YELLOW}Setting up Xorg (xinit only, no display manager)...${RC}"
    case "$PACKAGER" in
        pacman)
            "$ESCALATION_TOOL" "$PACKAGER" -S --needed --noconfirm xorg-xinit xorg-server
            ;;
        apt-get|nala)
            "$ESCALATION_TOOL" "$PACKAGER" install -y xinit xserver-xorg
            ;;
        *)
            printf "%b\n" "${RED}Unsupported package manager: $PACKAGER${RC}"
            exit 1
            ;;
    esac
    printf "%b\n" "${GREEN}Xorg installed successfully${RC}"
}

installDWMDeps() {
    printf "%b\n" "${YELLOW}Installing DWM dependencies...${RC}"
    case "$PACKAGER" in
        pacman)
            "$ESCALATION_TOOL" "$PACKAGER" -S --needed --noconfirm \
                base-devel libx11 libxinerama libxft imlib2 git unzip \
                flameshot nwg-look feh mate-polkit alsa-utils ghostty rofi \
                xclip xarchiver thunar tumbler tldr gvfs thunar-archive-plugin \
                dunst dex xscreensaver xorg-xprop polybar picom \
                xdg-user-dirs xdg-desktop-portal-gtk pipewire pavucontrol \
                gnome-keyring flatpak networkmanager network-manager-applet
            ;;
        apt-get|nala)
            "$ESCALATION_TOOL" "$PACKAGER" install -y \
                build-essential libx11-dev libxinerama-dev libxft-dev libimlib2-dev libx11-xcb-dev libxcb-res0-dev git unzip \
                flameshot feh mate-polkit alsa-utils rofi \
                xclip xarchiver thunar tumbler gvfs thunar-archive-plugin \
                dunst dex xscreensaver x11-utils polybar picom \
                xdg-user-dirs xdg-desktop-portal-gtk pipewire pavucontrol \
                gnome-keyring flatpak network-manager network-manager-gnome
            ;;
        *)
            printf "%b\n" "${RED}Unsupported package manager: $PACKAGER${RC}"
            exit 1
            ;;
    esac
    printf "%b\n" "${GREEN}DWM dependencies installed${RC}"
}

cloneAndBuildDWM() {
    [ ! -d "$HOME/.local/share" ] && mkdir -p "$HOME/.local/share/"
    
    if [ ! -d "$DWM_DIR" ]; then
        printf "%b\n" "${YELLOW}Cloning Rahul's DWM...${RC}"
        cd "$HOME/.local/share/" && git clone https://github.com/rahuljangirworks/dwm-rahul.git
    else
        printf "%b\n" "${GREEN}DWM directory exists, pulling latest...${RC}"
        cd "$DWM_DIR" && git pull
    fi
    
    printf "%b\n" "${YELLOW}Building DWM...${RC}"
    cd "$DWM_DIR" && "$ESCALATION_TOOL" make clean install
    printf "%b\n" "${GREEN}DWM built and installed${RC}"
}

installNerdFont() {
    FONT_NAME="MesloLGS Nerd Font Mono"
    FONT_DIR="$HOME/.local/share/fonts"
    FONT_URL="https://github.com/ryanoasis/nerd-fonts/releases/latest/download/Meslo.zip"

    if fc-list | grep -qi "Meslo"; then
        printf "%b\n" "${GREEN}Meslo Nerd Font already installed${RC}"
        return 0
    fi

    printf "%b\n" "${YELLOW}Installing Meslo Nerd Font...${RC}"
    mkdir -p "$FONT_DIR"
    TEMP_DIR=$(mktemp -d)
    curl -sSLo "$TEMP_DIR/${FONT_NAME}.zip" "$FONT_URL"
    unzip "$TEMP_DIR/${FONT_NAME}.zip" -d "$TEMP_DIR"
    mkdir -p "$FONT_DIR/$FONT_NAME"
    mv "$TEMP_DIR"/*.ttf "$FONT_DIR/$FONT_NAME"
    fc-cache -fv
    rm -rf "$TEMP_DIR"
    printf "%b\n" "${GREEN}Meslo Nerd Font installed${RC}"
}

copyConfigFolders() {
    printf "%b\n" "${YELLOW}Copying config folders...${RC}"
    [ ! -d ~/.config ] && mkdir -p ~/.config
    [ ! -d ~/.local/bin ] && mkdir -p ~/.local/bin

    # Ensure user owns their config directory (fixes potential root ownership from previous runs)
    if [ -d "$HOME/.config" ]; then
        "$ESCALATION_TOOL" chown -R "$USER:$USER" "$HOME/.config"
    fi

    # Copy scripts to local bin
    if [ -d "$DWM_DIR/scripts" ]; then
        cp -rf "$DWM_DIR/scripts/." "$HOME/.local/bin/"
        printf "%b\n" "${GREEN}Copied scripts to ~/.local/bin/${RC}"
    fi

    # Copy config folders
    if [ -d "$DWM_DIR/config" ]; then
        for dir in "$DWM_DIR/config/"*/; do
            dir_name=$(basename "$dir")
            target_dir="$HOME/.config/$dir_name"
            
            # Create target directory if it doesn't exist
            if [ ! -d "$target_dir" ]; then
                mkdir -p "$target_dir"
            fi

            # Copy contents (using /. to avoid nesting if dir exists)
            cp -rf "$dir". "$target_dir/"
            printf "%b\n" "${GREEN}Copied $dir_name to ~/.config/${RC}"
        done
    fi
}

setupXinitrc() {
    printf "%b\n" "${YELLOW}Setting up .xinitrc...${RC}"

    # Ensure user owns existing .xinitrc (fixes root ownership from sudo make install)
    if [ -f "$HOME/.xinitrc" ]; then
        "$ESCALATION_TOOL" chown "$USER:$USER" "$HOME/.xinitrc"
    fi
    
    # Backup existing .xinitrc
    if [ -f "$HOME/.xinitrc" ] && [ ! -f "$HOME/.xinitrc.bak" ]; then
        cp "$HOME/.xinitrc" "$HOME/.xinitrc.bak"
        printf "%b\n" "${YELLOW}Backed up existing .xinitrc${RC}"
    fi
    
    # Copy .xinitrc from dwm-rahul if it exists
    if [ -f "$DWM_DIR/.xinitrc" ]; then
        cp "$DWM_DIR/.xinitrc" "$HOME/.xinitrc"
        printf "%b\n" "${GREEN}.xinitrc copied from dwm-rahul${RC}"
    else
        # Create a basic .xinitrc
        cat > "$HOME/.xinitrc" << 'EOF'
#!/bin/sh
exec dwm
EOF
        printf "%b\n" "${GREEN}Created basic .xinitrc${RC}"
    fi
}

configureBackgrounds() {
    PIC_DIR="$HOME/Pictures"
    BG_DIR="$PIC_DIR/backgrounds"

    [ ! -d "$PIC_DIR" ] && mkdir -p "$PIC_DIR"

    if [ ! -d "$BG_DIR" ]; then
        printf "%b\n" "${YELLOW}Downloading Rahul's backgrounds...${RC}"
        if git clone https://github.com/rahuljangirworks/background.git "$BG_DIR"; then
            printf "%b\n" "${GREEN}Backgrounds downloaded to $BG_DIR${RC}"
        else
            printf "%b\n" "${RED}Failed to clone backgrounds repository${RC}"
            return 1
        fi
    else
        printf "%b\n" "${GREEN}Backgrounds already exist at $BG_DIR${RC}"
    fi
}

printInstructions() {
    printf "%b\n" "${GREEN}========================================${RC}"
    printf "%b\n" "${GREEN}DWM Setup Complete!${RC}"
    printf "%b\n" "${GREEN}========================================${RC}"
    printf "%b\n" "${CYAN}To start DWM, run: startx${RC}"
    printf "%b\n" "${CYAN}DWM installed at: $DWM_DIR${RC}"
    printf "%b\n" "${CYAN}Backgrounds at: ~/Pictures/backgrounds${RC}"
    printf "%b\n" "${GREEN}========================================${RC}"
}

# Main execution
checkEnv
checkEscalationTool
setupXorg
installDWMDeps
cloneAndBuildDWM
installNerdFont
copyConfigFolders
setupXinitrc
configureBackgrounds
printInstructions
