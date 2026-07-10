#!/bin/sh

# Description: Setup Rahul's customized mybash configuration with machine-role theme selection
# Keep the four roles stable: rahul, work, server, test. They are used as
# terminal/SSH reminders for what kind of machine the shell is running on.
case "$0" in
    */*) script_path="$0" ;;
    *) script_path="$(command -v -- "$0" 2>/dev/null || printf "%s\n" "$0")" ;;
esac
SCRIPT_DIR="$(dirname "$script_path")"
SCRIPT_DIR="$(cd "$SCRIPT_DIR" && pwd)"
unset script_path

# Repository: https://github.com/rahuljangirworks/mybash

. "$SCRIPT_DIR/../../common-script.sh"

gitpath="$HOME/.local/share/mybash"
THEMES_DIR="$SCRIPT_DIR/themes"
MYBASH_THEMES_DIR="$gitpath/themes"
REQUESTED_THEME="${MYBASH_THEME:-${LINUTIL_THEME:-}}"
ASK_THEME=0

usage() {
    printf "%s\n" "Usage: $0 [--theme rahul|work|server|test] [--ask-theme]"
    printf "%s\n" ""
    printf "%s\n" "Machine role themes:"
    printf "%s\n" "  rahul   Personal/default machine"
    printf "%s\n" "  work    Work machine"
    printf "%s\n" "  server  SSH/server machine reminder"
    printf "%s\n" "  test    Test/sandbox/warning machine"
}

parseArgs() {
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --theme)
                shift
                if [ "$#" -eq 0 ]; then
                    printf "%s\n" "Missing value for --theme" >&2
                    usage >&2
                    exit 1
                fi
                REQUESTED_THEME="$1"
                ;;
            --theme=*)
                REQUESTED_THEME="${1#--theme=}"
                ;;
            --ask-theme)
                ASK_THEME=1
                REQUESTED_THEME=""
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                printf "%s\n" "Unknown option: $1" >&2
                usage >&2
                exit 1
                ;;
        esac
        shift
    done
}

ensureBashrcLocal() {
    bashrc_local="$HOME/.bashrc.local"

    if [ -L "$bashrc_local" ] && [ ! -e "$bashrc_local" ]; then
        printf "%b\n" "${YELLOW}Replacing broken ~/.bashrc.local symlink${RC}"
        rm -f "$bashrc_local"
    fi

    if [ ! -e "$bashrc_local" ]; then
        {
            printf "%s\n" "#!/usr/bin/env bash"
            printf "%s\n" "# Rahul's Personal Bash Customizations"
        } > "$bashrc_local"
    fi
}

getThemeFile() {
    theme_name="$1"
    theme_ext="$2"
    if [ -f "$MYBASH_THEMES_DIR/${theme_name}.${theme_ext}" ]; then
        printf "%s\n" "$MYBASH_THEMES_DIR/${theme_name}.${theme_ext}"
    else
        printf "%s\n" "$THEMES_DIR/${theme_name}.${theme_ext}"
    fi
}

normalizeThemeChoice() {
    case "$1" in
        1|rahul) printf "%s\n" "rahul" ;;
        2|work) printf "%s\n" "work" ;;
        3|server) printf "%s\n" "server" ;;
        4|test) printf "%s\n" "test" ;;
        *) return 1 ;;
    esac
}

detectThemeMode() {
    dwm_themes="${XDG_CONFIG_HOME:-$HOME/.config}/dwm-titus/themes.toml"
    if [ -f "$dwm_themes" ]; then
        active_theme=$(awk '
            /^\[active\]/ { active = 1; next }
            /^\[/ { active = 0 }
            active && $1 == "theme" {
                sub(/^[^=]*=[[:space:]]*/, "")
                gsub(/"/, "")
                sub(/[[:space:]]+#.*$/, "")
                sub(/[[:space:]]+$/, "")
                print
                exit
            }
        ' "$dwm_themes")
        if [ -n "$active_theme" ]; then
            dark_mode=$(awk -v section="[theme.$active_theme]" '
                /^\[/ { in_section = ($0 == section); next }
                in_section && $1 == "dark_mode" {
                    sub(/^[^=]*=[[:space:]]*/, "")
                    sub(/[[:space:]]+#.*$/, "")
                    sub(/[[:space:]]+$/, "")
                    print
                    exit
                }
            ' "$dwm_themes")
            if [ "$dark_mode" = "false" ]; then
                printf "%s\n" "light"
                return
            fi
        fi
    fi
    printf "%s\n" "dark"
}

installDepend() {
    if [ ! -f "/usr/share/bash-completion/bash_completion" ] || ! command_exists bash tar bat tree unzip fc-list git; then
        printf "%b\n" "${YELLOW}Installing dependencies...${RC}"
        case "$PACKAGER" in
            pacman)
                "$ESCALATION_TOOL" "$PACKAGER" -S --needed --noconfirm bash bash-completion tar bat tree unzip fontconfig git fzf fastfetch
                ;;
            apk)
                "$ESCALATION_TOOL" "$PACKAGER" add bash bash-completion tar bat tree unzip fontconfig git fzf fastfetch
                ;;
            xbps-install)
                "$ESCALATION_TOOL" "$PACKAGER" -Sy bash bash-completion tar bat tree unzip fontconfig git fzf fastfetch
                ;;
            *)
                "$ESCALATION_TOOL" "$PACKAGER" install -y bash bash-completion tar bat tree unzip fontconfig git fzf fastfetch
                ;;
        esac
    fi
}

cloneMyBash() {
    if [ -d "$gitpath" ]; then
        printf "%b\n" "${YELLOW}Removing old mybash installation...${RC}"
        rm -rf "$gitpath"
    fi
    mkdir -p "$HOME/.local/share"
    printf "%b\n" "${CYAN}Cloning Rahul's mybash fork...${RC}"
    cd "$HOME" && git clone -b dev https://github.com/rahuljangirworks/mybash.git "$gitpath"
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

selectTheme() {
    requested_theme="$REQUESTED_THEME"
    if [ "$ASK_THEME" -ne 1 ] && [ -n "$requested_theme" ]; then
        if THEME_CHOICE="$(normalizeThemeChoice "$requested_theme")"; then
            printf "%b\n" "${GREEN}Selected theme: $THEME_CHOICE${RC}"
            return
        fi
        if [ ! -t 0 ]; then
            printf "%b\n" "${RED}Unknown theme '$requested_theme'. Use rahul, work, server, or test.${RC}"
            exit 1
        fi
        printf "%b\n" "${YELLOW}Ignoring unknown theme '$requested_theme'; asking manually.${RC}"
    fi

    if [ "$ASK_THEME" -ne 1 ] && [ -z "$requested_theme" ] && [ ! -t 0 ] && [ -r "$HOME/.config/mybash/theme.env" ]; then
        requested_theme=$(awk -F= '
            $1 == "export MYBASH_THEME" || $1 == "export LINUTIL_THEME" {
                gsub(/"/, "", $2)
                print $2
                exit
            }
        ' "$HOME/.config/mybash/theme.env" 2>/dev/null)
    fi
    if [ "$ASK_THEME" -ne 1 ] && [ -z "$requested_theme" ] && [ ! -t 0 ]; then
        requested_theme="rahul"
    fi
    if [ "$ASK_THEME" -ne 1 ] && [ -n "$requested_theme" ]; then
        if THEME_CHOICE="$(normalizeThemeChoice "$requested_theme")"; then
            printf "%b\n" "${GREEN}Selected theme: $THEME_CHOICE${RC}"
            return
        fi
        printf "%b\n" "${RED}Unknown saved theme '$requested_theme'. Use rahul, work, server, or test.${RC}"
        exit 1
    fi

    printf "%b\n" ""
    printf "%b\n" "${CYAN}╔══════════════════════════════════════════════╗${RC}"
    printf "%b\n" "${CYAN}║       Select Theme (Starship + Fastfetch)    ║${RC}"
    printf "%b\n" "${CYAN}╠══════════════════════════════════════════════╣${RC}"
    printf "%b\n" "${CYAN}║${RC}  ${YELLOW}1)${RC} Rahul   — Warm bronze/copper  ${GREEN}██████${RC}  ${CYAN}║${RC}"
    printf "%b\n" "${CYAN}║${RC}  ${YELLOW}2)${RC} Work    — Cool blue/teal      ${BLUE}██████${RC}  ${CYAN}║${RC}"
    printf "%b\n" "${CYAN}║${RC}  ${YELLOW}3)${RC} Server  — Green/emerald       ${GREEN}██████${RC}  ${CYAN}║${RC}"
    printf "%b\n" "${CYAN}║${RC}  ${YELLOW}4)${RC} Test    — Red/coral/warning   ${RED}██████${RC}  ${CYAN}║${RC}"
    printf "%b\n" "${CYAN}╚══════════════════════════════════════════════╝${RC}"
    printf "%b\n" ""

    THEME_CHOICE=""
    while [ -z "$THEME_CHOICE" ]; do
        printf "${YELLOW}Enter theme number [1-4]: ${RC}"
        read -r choice
        if THEME_CHOICE="$(normalizeThemeChoice "$choice")"; then
            :
        else
            THEME_CHOICE=""
            printf "%b\n" "${RED}Invalid choice. Enter 1-4.${RC}"
        fi
    done

    printf "%b\n" "${GREEN}Selected theme: $THEME_CHOICE${RC}"
}

applyTheme() {
    THEME_FILE="$(getThemeFile "$THEME_CHOICE" toml)"

    if [ ! -f "$THEME_FILE" ]; then
        printf "%b\n" "${RED}Theme file not found: $THEME_FILE${RC}"
        printf "%b\n" "${YELLOW}Falling back to rahul theme...${RC}"
        THEME_CHOICE="rahul"
        THEME_FILE="$(getThemeFile "$THEME_CHOICE" toml)"
    fi
    if [ ! -f "$THEME_FILE" ]; then
        printf "%b\n" "${RED}No usable Starship theme found for '$THEME_CHOICE'.${RC}"
        exit 1
    fi

    mkdir -p "$HOME/.config"
    cp "$THEME_FILE" "$HOME/.config/starship.toml"
    printf "%b\n" "${GREEN}Theme '$THEME_CHOICE' applied to ~/.config/starship.toml${RC}"

    # Apply matching fastfetch config
    FASTFETCH_THEME="$(getThemeFile "$THEME_CHOICE" jsonc)"
    if [ -f "$FASTFETCH_THEME" ]; then
        mkdir -p "$HOME/.config/fastfetch"
        cp "$FASTFETCH_THEME" "$HOME/.config/fastfetch/config.jsonc"
        printf "%b\n" "${GREEN}Fastfetch theme '$THEME_CHOICE' applied to ~/.config/fastfetch/config.jsonc${RC}"
    fi

    THEME_MODE="$(detectThemeMode)"
    mkdir -p "$HOME/.config/mybash"
    {
        printf "%s\n" "# Auto-generated by rahul-mybash-setup.sh - do not edit manually."
        printf "export MYBASH_THEME=\"%s\"\n" "$THEME_CHOICE"
        printf "export LINUTIL_THEME=\"%s\"\n" "$THEME_CHOICE"
        printf "export MYBASH_THEME_MODE=\"%s\"\n" "$THEME_MODE"
        printf "export LINUTIL_THEME_MODE=\"%s\"\n" "$THEME_MODE"
    } > "$HOME/.config/mybash/theme.env"
    printf "%b\n" "${GREEN}Theme environment saved to ~/.config/mybash/theme.env${RC}"

    BASHRC_LOCAL="$HOME/.bashrc.local"
    ensureBashrcLocal
    sed -i '/^export LINUTIL_THEME=/d;/^export MYBASH_THEME=/d;/^export LINUTIL_THEME_MODE=/d;/^export MYBASH_THEME_MODE=/d' "$BASHRC_LOCAL" 2>/dev/null || true
    printf "export LINUTIL_THEME=\"%s\"\n" "$THEME_CHOICE" >> "$BASHRC_LOCAL" 2>/dev/null
    printf "export MYBASH_THEME=\"%s\"\n" "$THEME_CHOICE" >> "$BASHRC_LOCAL" 2>/dev/null
    printf "export LINUTIL_THEME_MODE=\"%s\"\n" "$THEME_MODE" >> "$BASHRC_LOCAL" 2>/dev/null
    printf "export MYBASH_THEME_MODE=\"%s\"\n" "$THEME_MODE" >> "$BASHRC_LOCAL" 2>/dev/null
    if [ $? -eq 0 ]; then
        printf "%b\n" "${GREEN}Theme saved to ~/.bashrc.local${RC}"
    else
        printf "%b\n" "${YELLOW}Theme applied but could not save to ~/.bashrc.local (non-critical)${RC}"
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

    # Link .bashrc.local if it exists (for machine-specific configs)
    if [ -f "$gitpath/.bashrc.local" ]; then
        printf "%b\n" "${YELLOW}Copying .bashrc.local template...${RC}"
        if [ ! -e "$HOME/.bashrc.local" ]; then
            cp "$gitpath/.bashrc.local" "$HOME/.bashrc.local"
        fi
    fi

    printf "%b\n" "${GREEN}Done! Restart your shell to see the changes.${RC}"
    printf "%b\n" "${CYAN}Your mybash is installed at: $gitpath${RC}"
    printf "%b\n" "${CYAN}Theme: $THEME_CHOICE | Starship: ~/.config/starship.toml | Fastfetch: ~/.config/fastfetch/config.jsonc${RC}"
}

# Main execution
parseArgs "$@"
checkEnv
checkEscalationTool
installDepend
cloneMyBash
installFont
installStarshipAndFzf
installZoxide
selectTheme
applyTheme
linkConfig
