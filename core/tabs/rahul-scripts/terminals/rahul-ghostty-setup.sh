#!/bin/sh -e

# Description: Setup Rahul's customized Ghostty configuration
# Repository: https://github.com/rahuljangirworks/dwm-jangir

. ../../common-script.sh

installGhostty() {
    if ! command_exists ghostty; then
        printf "%b\n" "${YELLOW}Installing Ghostty...${RC}"
        case "$PACKAGER" in
            pacman)
                "$ESCALATION_TOOL" "$PACKAGER" -S --needed --noconfirm ghostty
                ;;
            apk)
                "$ESCALATION_TOOL" "$PACKAGER" add ghostty
                ;;
            xbps-install)
                "$ESCALATION_TOOL" "$PACKAGER" -Sy ghostty
                ;;
            dnf)
                # Ghostty is in the official Fedora repos since Fedora 41.
                # Try the official repo first; fall back to the scottames COPR
                # only if the package is not available (e.g., older Fedora).
                if "$ESCALATION_TOOL" dnf install -y ghostty 2>/dev/null; then
                    printf "%b\n" "${GREEN}✓ Ghostty installed from official Fedora repository${RC}"
                else
                    printf "%b\n" "${YELLOW}→ Ghostty not in official repos, enabling scottames/ghostty COPR...${RC}"
                    "$ESCALATION_TOOL" dnf copr enable -y scottames/ghostty
                    "$ESCALATION_TOOL" dnf install -y ghostty
                fi
                ;;
            *)
                "$ESCALATION_TOOL" "$PACKAGER" install -y ghostty
                ;;
        esac
    else
        printf "%b\n" "${GREEN}Ghostty is already installed.${RC}"
    fi
}

setupGhosttyConfig() {
    printf "%b\n" "${YELLOW}Setting up Rahul's Ghostty config...${RC}"

    # Backup existing config if it exists and no backup exists yet
    if [ -d "${HOME}/.config/ghostty" ] && [ ! -d "${HOME}/.config/ghostty-bak" ]; then
        printf "%b\n" "${YELLOW}Backing up existing Ghostty config...${RC}"
        cp -r "${HOME}/.config/ghostty" "${HOME}/.config/ghostty-bak"
    fi

    mkdir -p "${HOME}/.config/ghostty/"

    # Remove stale symlinks or files so curl can write fresh configs
    rm -f "${HOME}/.config/ghostty/config"

    # Download config from Rahul's dwm-jangir repo (avoids merge conflicts with upstream)
    printf "%b\n" "${CYAN}Downloading config from rahuljangirworks/dwm-jangir...${RC}"
    curl -fsSL -o "$HOME/.config/ghostty/config" \
        "https://raw.githubusercontent.com/rahuljangirworks/dwm-jangir/dev/config/ghostty/config"

    printf "%b\n" "${GREEN}Ghostty configuration installed!${RC}"
    printf "%b\n" "${CYAN}Config location: ~/.config/ghostty/config${RC}"
}

# Main execution
checkEnv
checkEscalationTool
installGhostty
setupGhosttyConfig
