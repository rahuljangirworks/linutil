#!/bin/sh -e

# Description: Setup Rahul's customized mybash configuration
# Repository: https://github.com/rahuljangirworks/mybash

. ../common-script.sh

gitpath="$HOME/.local/share/mybash"

installDepend() {
    if [ ! -f "/usr/share/bash-completion/bash_completion" ] || ! command_exists bash tar bat tree unzip fc-list git; then
        printf "%b\n" "${YELLOW}Installing dependencies...${RC}"
        case "$PACKAGER" in
            pacman)
                "$ESCALATION_TOOL" "$PACKAGER" -S --needed --noconfirm bash bash-completion tar bat tree unzip fontconfig git fzf 
                ;;
            apk)
                "$ESCALATION_TOOL" "$PACKAGER" add bash bash-completion tar bat tree unzip fontconfig git
                ;;
            xbps-install)
                "$ESCALATION_TOOL" "$PACKAGER" -Sy bash bash-completion tar bat tree unzip fontconfig git
                ;;
            *)
                "$ESCALATION_TOOL" "$PACKAGER" install -y bash bash-completion tar bat tree unzip fontconfig git
                ;;
        esac
    fi
}

cloneMyBash() {
    # Check if the dir exists before attempting to clone into it.
    if [ -d "$gitpath" ]; then
        printf "%b\n" "${YELLOW}Removing old mybash installation...${RC}"
        rm -rf "$gitpath"
    fi
    mkdir -p "$HOME/.local/share"
    printf "%b\n" "${CYAN}Cloning Rahul's mybash fork...${RC}"
    cd "$HOME" && git clone https://github.com/rahuljangirworks/mybash.git "$gitpath"
}

installFont() {
    FONT_NAME="MesloLGS Nerd Font Mono"
    if fc-list :family | grep -iq "$FONT_NAME"; then
        printf "%b\n" "${GREEN}Font '$FONT_NAME' is already installed.${RC}"
    else
        printf "%b\n" "${YELLOW}Installing font '$FONT_NAME'${RC}"
        FONT_URL="https://github.com/ryanoasis/nerd-fonts/releases/latest/download/Meslo.zip"
        FONT_DIR="$HOME/.local/share/fonts"
        TEMP_DIR=$(mktemp -d)
        curl -sSLo "$TEMP_DIR"/"${FONT_NAME}".zip "$FONT_URL"
        unzip "$TEMP_DIR"/"${FONT_NAME}".zip -d "$TEMP_DIR"
        mkdir -p "$FONT_DIR"/"$FONT_NAME"
        mv "${TEMP_DIR}"/*.ttf "$FONT_DIR"/"$FONT_NAME"
        fc-cache -fv
        rm -rf "${TEMP_DIR}"
        printf "%b\n" "${GREEN}'$FONT_NAME' installed successfully.${RC}"
    fi
}

installStarshipAndFzf() {
    if command_exists starship; then
        printf "%b\n" "${GREEN}Starship already installed${RC}"
    else
        printf "%b\n" "${YELLOW}Installing Starship prompt...${RC}"
        if [ "$PACKAGER" = "eopkg" ]; then
            "$ESCALATION_TOOL" "$PACKAGER" install -y starship || {
                printf "%b\n" "${RED}Failed to install starship with Solus!${RC}"
                exit 1
            }
        else
            curl -sSL https://starship.rs/install.sh | "$ESCALATION_TOOL" sh || {
                printf "%b\n" "${RED}Failed to install starship!${RC}"
                exit 1
            }
        fi
    fi

    if command_exists fzf; then
        printf "%b\n" "${GREEN}Fzf already installed${RC}"
    else
        if [ -d "$HOME/.fzf" ]; then
            printf "%b\n" "${YELLOW}fzf directory already exists. Updating...${RC}"
            cd "$HOME/.fzf" && git pull
        else
            printf "%b\n" "${YELLOW}Installing fzf...${RC}"
            git clone --depth 1 https://github.com/junegunn/fzf.git ~/.fzf
        fi
        "$ESCALATION_TOOL" ~/.fzf/install
    fi
}

installZoxide() {
    if command_exists zoxide; then
        printf "%b\n" "${GREEN}Zoxide already installed${RC}"
        return
    fi

    printf "%b\n" "${YELLOW}Installing Zoxide...${RC}"
    if ! curl -sSL https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | sh; then
        printf "%b\n" "${RED}Something went wrong during zoxide install!${RC}"
        exit 1
    fi
}

linkConfig() {
    OLD_BASHRC="$HOME/.bashrc"
    if [ -e "$OLD_BASHRC" ] && [ ! -e "$HOME/.bashrc.bak" ]; then
        printf "%b\n" "${YELLOW}Backing up old .bashrc to $HOME/.bashrc.bak${RC}"
        if ! mv "$OLD_BASHRC" "$HOME/.bashrc.bak"; then
            printf "%b\n" "${RED}Can't move the old bash config file!${RC}"
            exit 1
        fi
    fi

    printf "%b\n" "${YELLOW}Linking Rahul's bash config...${RC}"
    ln -svf "$gitpath/.bashrc" "$HOME/.bashrc" || {
        printf "%b\n" "${RED}Failed to create symbolic link for .bashrc${RC}"
        exit 1
    }

    mkdir -p "$HOME/.config"
    ln -svf "$gitpath/starship.toml" "$HOME/.config/starship.toml" || {
        printf "%b\n" "${RED}Failed to create symbolic link for starship.toml${RC}"
        exit 1
    }

    # Link .bashrc.local if it exists (for machine-specific configs)
    if [ -f "$gitpath/.bashrc.local" ]; then
        printf "%b\n" "${YELLOW}Copying .bashrc.local template...${RC}"
        if [ ! -f "$HOME/.bashrc.local" ]; then
            cp "$gitpath/.bashrc.local" "$HOME/.bashrc.local"
        fi
    fi

    printf "%b\n" "${GREEN}Done! Restart your shell to see the changes.${RC}"
    printf "%b\n" "${CYAN}Your mybash is installed at: $gitpath${RC}"
}

# Main execution
checkEnv
checkEscalationTool
installDepend
cloneMyBash
installFont
installStarshipAndFzf
installZoxide
linkConfig
