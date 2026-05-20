#!/bin/sh -e

# Description: Install AionUi — AI Cowork app for CLI agents (OpenCode, Claude Code, Gemini CLI, etc.)
# Latest: v1.9.25
# Works on: Arch, Debian, Fedora, openSUSE, Void, Alpine, Solus

. ../common-script.sh

APP_NAME="AionUi"
LATEST_VERSION="1.9.25"
GITHUB_REPO="iOfficeAI/AionUi"

clear 2>/dev/null || true
printf "%b\n" "${CYAN}=================================================================${RC}"
printf "%b\n" "${YELLOW}        $APP_NAME v${LATEST_VERSION} Installer                                  ${RC}"
printf "%b\n" "${CYAN}=================================================================${RC}"
printf "%b\n" "${GREEN}  - Free, open-source 24/7 Cowork app with AI Agents${RC}"
printf "%b\n" "${GREEN}  - Supports: OpenCode, Claude Code, Gemini CLI, Qwen, etc.${RC}"
printf "%b\n" "${GREEN}  - Built-in AI agent engine — works out of the box${RC}"
printf "%b\n" "${GREEN}  - Customizable assistant profiles${RC}"
printf "%b\n" "${CYAN}=================================================================${RC}"
echo ""

get_latest_version() {
    printf "%b\n" "${CYAN}[*] Checking latest AionUi version from GitHub...${RC}"
    LATEST_VERSION=$(curl -fsSL "https://api.github.com/repos/$GITHUB_REPO/releases/latest" \
        | sed -n 's/.*"tag_name": "v\([^"]*\)".*/\1/p' \
        | head -n 1)
    if [ -z "$LATEST_VERSION" ]; then
        printf "%b\n" "${YELLOW}[~] Could not fetch latest version, using fallback: $LATEST_VERSION${RC}"
    else
        printf "%b\n" "${GREEN}[✓] Latest version: v$LATEST_VERSION${RC}"
    fi
}

install_dependencies() {
    printf "%b\n" "${CYAN}[*] Installing dependencies...${RC}"

    # Dependencies from AUR: alsa-lib, gtk3, libcups, mesa, nss
    for pkg in alsa-lib gtk3 libcups mesa nss; do
        case "$PACKAGER" in
            pacman)
                if ! pacman -Q "$pkg" >/dev/null 2>&1; then
                    printf "%b\n" "${YELLOW}[*] Installing $pkg...${RC}"
                    "$ESCALATION_TOOL" "$PACKAGER" -S --needed --noconfirm "$pkg"
                else
                    printf "%b\n" "${GREEN}[✓] $pkg already installed${RC}"
                fi
                ;;
            apt-get|nala)
                if ! dpkg -l "$pkg" 2>/dev/null | grep -q '^ii'; then
                    printf "%b\n" "${YELLOW}[*] Installing $pkg...${RC}"
                    "$ESCALATION_TOOL" "$PACKAGER" update
                    "$ESCALATION_TOOL" "$PACKAGER" install -y "$pkg"
                else
                    printf "%b\n" "${GREEN}[✓] $pkg already installed${RC}"
                fi
                ;;
            dnf)
                if ! rpm -q "$pkg" >/dev/null 2>&1; then
                    printf "%b\n" "${YELLOW}[*] Installing $pkg...${RC}"
                    "$ESCALATION_TOOL" "$PACKAGER" install -y "$pkg"
                else
                    printf "%b\n" "${GREEN}[✓] $pkg already installed${RC}"
                fi
                ;;
            zypper)
                if ! rpm -q "$pkg" >/dev/null 2>&1; then
                    printf "%b\n" "${YELLOW}[*] Installing $pkg...${RC}"
                    "$ESCALATION_TOOL" "$PACKAGER" install -y "$pkg"
                else
                    printf "%b\n" "${GREEN}[✓] $pkg already installed${RC}"
                fi
                ;;
            *)
                printf "%b\n" "${YELLOW}[~] Skipping $pkg (manual install may be needed)${RC}"
                ;;
        esac
    done
}

install_aionui() {
    printf "\n%b\n" "${CYAN}━━━ Installing $APP_NAME ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RC}"

    case "$PACKAGER" in
        pacman)
            # Remove conflicting debug packages first
            if pacman -Q aionui-bin-debug >/dev/null 2>&1; then
                printf "%b\n" "${YELLOW}[*] Removing conflicting aionui-bin-debug...${RC}"
                "$ESCALATION_TOOL" pacman -Rns --noconfirm aionui-bin-debug 2>/dev/null || true
            fi
            if pacman -Q github-desktop-plus-bin-debug >/dev/null 2>&1; then
                printf "%b\n" "${YELLOW}[*] Removing conflicting github-desktop-plus-bin-debug...${RC}"
                "$ESCALATION_TOOL" pacman -Rns --noconfirm github-desktop-plus-bin-debug 2>/dev/null || true
            fi

            # Check AUR first
            if pacman -Q aionui-bin >/dev/null 2>&1 || pacman -Q aionui >/dev/null 2>&1; then
                CURRENT=$(pacman -Q aionui-bin 2>/dev/null | awk '{print $2}' || pacman -Q aionui 2>/dev/null | awk '{print $2}')
                printf "%b\n" "${GREEN}[✓] AionUi already installed — v$CURRENT${RC}"
                if [ "$CURRENT" != "$LATEST_VERSION" ] && [ "$CURRENT" != "${LATEST_VERSION}-1" ] && [ "$CURRENT" != "${LATEST_VERSION}-2" ]; then
                    printf "%b\n" "${YELLOW}[*] New version v$LATEST_VERSION available. Updating...${RC}"
                    "$AUR_HELPER" -Syu --noconfirm aionui-bin 2>/dev/null || {
                        printf "%b\n" "${YELLOW}[~] AUR update failed, falling back to manual install.${RC}"
                        install_via_deb
                    }
                fi
                return 0
            fi

            # Try AUR install
            printf "%b\n" "${YELLOW}[*] Installing from AUR (aionui-bin)...${RC}"
            "$AUR_HELPER" -S --needed --noconfirm aionui-bin 2>/dev/null || {
                printf "%b\n" "${YELLOW}[~] AUR install failed.${RC}"
                printf "%b\n" "${YELLOW}[*] Falling back to manual .deb extraction...${RC}"
                install_via_deb
            }
            ;;
        apt-get|nala)
            install_via_deb
            ;;
        dnf|zypper)
            install_via_deb
            ;;
        *)
            install_via_deb
            ;;
    esac
}

install_via_deb() {
    DEB_URL="https://github.com/$GITHUB_REPO/releases/download/v${LATEST_VERSION}/AionUi-${LATEST_VERSION}-linux-amd64.deb"
    TMP_DIR=$(mktemp -d)
    TMP_DEB="$TMP_DIR/aionui.deb"

    printf "%b\n" "${YELLOW}[*] Downloading AionUi v$LATEST_VERSION...${RC}"
    printf "%b\n" "${CYAN}    URL: $DEB_URL${RC}"
    curl -fL "$DEB_URL" -o "$TMP_DEB" || {
        printf "%b\n" "${RED}[✗] Download failed.${RC}"
        rm -rf "$TMP_DIR"
        return 1
    }

    printf "%b\n" "${YELLOW}[*] Extracting .deb package...${RC}"

    if command_exists dpkg; then
        # Use dpkg to extract
        "$ESCALATION_TOOL" dpkg -i "$TMP_DEB" || {
            printf "%b\n" "${YELLOW}[~] dpkg install had dependency issues, fixing...${RC}"
            case "$PACKAGER" in
                apt-get|nala)
                    "$ESCALATION_TOOL" "$PACKAGER" install -f -y
                    ;;
            esac
        }
    elif command_exists bsdtar; then
        # Arch Linux: use bsdtar to extract .deb (which is an ar archive)
        cd "$TMP_DIR"
        bsdtar -xf "$TMP_DEB" data.tar.* 2>/dev/null || bsdtar -xf "$TMP_DEB" 2>/dev/null
        # Extract the data archive into root
        for datafile in data.tar.*; do
            if [ -f "$datafile" ]; then
                "$ESCALATION_TOOL" bsdtar -xf "$datafile" -C / 2>/dev/null && break
            fi
        done
        cd - >/dev/null
    else
        # Fallback: use ar + tar
        cd "$TMP_DIR"
        ar x "$TMP_DEB" 2>/dev/null
        for datafile in data.tar.*; do
            if [ -f "$datafile" ]; then
                "$ESCALATION_TOOL" tar -xf "$datafile" -C / 2>/dev/null && break
            fi
        done
        cd - >/dev/null
    fi

    rm -rf "$TMP_DIR"
    printf "%b\n" "${GREEN}[✓] AionUi installed via .deb extraction${RC}"
}

verify_install() {
    printf "\n%b\n" "${CYAN}━━━ Verification ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RC}"

    # AionUi installs to /opt/AionUi/AionUi
    if [ -x /opt/AionUi/AionUi ]; then
        printf "%b\n" "${GREEN}[✓] $APP_NAME installed at /opt/AionUi/AionUi${RC}"
    elif command_exists aionui || [ -f /usr/bin/aionui ] || [ -f /usr/local/bin/aionui ]; then
        printf "%b\n" "${GREEN}[✓] $APP_NAME installed${RC}"
    elif [ -f /usr/share/applications/AionUi.desktop ] || [ -f /usr/share/applications/aionui.desktop ]; then
        printf "%b\n" "${GREEN}[✓] $APP_NAME desktop entry found${RC}"
    elif pacman -Q aionui-bin >/dev/null 2>&1 || pacman -Q aionui >/dev/null 2>&1; then
        printf "%b\n" "${GREEN}[✓] $APP_NAME installed (pacman confirmed)${RC}"
    else
        printf "%b\n" "${RED}[✗] Installation may have failed. Check output above.${RC}"
        exit 1
    fi

    printf "%b\n" "${GREEN}=================================================================${RC}"
    printf "%b\n" "${GREEN}  $APP_NAME installation complete!${RC}"
    printf "%b\n" "${CYAN}  Launch: AionUi  (or find 'AionUi' in app menu)${RC}"
    printf "%b\n" "${CYAN}  First run: Sign in with Google or enter any API key${RC}"
    printf "%b\n" "${GREEN}=================================================================${RC}"
}

checkEnv
checkEscalationTool
checkAURHelper
get_latest_version
install_dependencies
install_aionui
verify_install
