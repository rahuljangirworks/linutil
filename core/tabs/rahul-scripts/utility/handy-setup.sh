#!/bin/sh -e

# Description: Install Handy (open-source speech-to-text) from GitHub releases
#              and configure it to start silently in the background after login.
# Homepage:    https://handy.computer
# GitHub:      https://github.com/cjpais/Handy
# Rerunnable:  Yes - skips completed steps

. ../../common-script.sh

HANDY_INSTALL_DIR="$HOME/.local/share/handy"
HANDY_BIN="$HOME/.local/bin/handy"

# ── Detect architecture ───────────────────────────────────────────────────────

detectArch() {
    ARCH=$(uname -m)
    case "$ARCH" in
        x86_64)         ARCH_TAG="amd64"  ; ARCH_RPM="x86_64"  ; ARCH_AI="amd64"   ;;
        aarch64|arm64)  ARCH_TAG="arm64"  ; ARCH_RPM="aarch64" ; ARCH_AI="aarch64" ;;
        *)
            printf "%b\n" "${RED}✗ Unsupported architecture: $ARCH${RC}"
            exit 1
            ;;
    esac
}

# ── Fetch latest release version from GitHub ─────────────────────────────────

fetchLatestVersion() {
    LATEST_VERSION=$(curl -s https://api.github.com/repos/cjpais/Handy/releases/latest \
        | grep '"tag_name"' | head -1 | cut -d '"' -f 4)

    if [ -z "$LATEST_VERSION" ]; then
        printf "%b\n" "${YELLOW}Could not fetch latest version from GitHub API, using fallback v0.8.3${RC}"
        LATEST_VERSION="v0.8.3"
    fi

    # Strip leading 'v' for filenames
    VERSION_NUM="${LATEST_VERSION#v}"
    printf "%b\n" "${CYAN}Latest Handy version: $LATEST_VERSION${RC}"
}

# ── Check if already installed and up to date ─────────────────────────────────

isInstalled() {
    # Check native package install
    case "$PACKAGER" in
        apt-get|nala)
            dpkg -l handy 2>/dev/null | grep -q '^ii' && return 0
            ;;
        dnf|yum|zypper)
            rpm -q handy 2>/dev/null | grep -q handy && return 0
            ;;
        pacman)
            pacman -Qq handy 2>/dev/null && return 0
            ;;
    esac

    # Check AppImage install
    [ -f "$HANDY_BIN" ] && return 0

    return 1
}

# ── Install Handy ─────────────────────────────────────────────────────────────

installHandy() {
    detectArch
    fetchLatestVersion

    if isInstalled; then
        printf "%b\n" "${GREEN}✓ Handy already installed${RC}"
        return 0
    fi

    printf "%b\n" "${YELLOW}Installing Handy $LATEST_VERSION...${RC}"

    BASE_URL="https://github.com/cjpais/Handy/releases/download/$LATEST_VERSION"

    case "$PACKAGER" in
        apt-get|nala)
            # .deb — native package install
            DEB_FILE="Handy_${VERSION_NUM}_${ARCH_TAG}.deb"
            TEMP_DEB=$(mktemp --suffix=.deb)
            printf "%b\n" "${YELLOW}Downloading $DEB_FILE...${RC}"
            curl -sL "$BASE_URL/$DEB_FILE" -o "$TEMP_DEB"
            "$ESCALATION_TOOL" apt-get install -y "$TEMP_DEB"
            rm -f "$TEMP_DEB"
            printf "%b\n" "${GREEN}✓ Handy installed via .deb${RC}"
            ;;

        dnf|yum)
            # .rpm — native package install
            RPM_FILE="Handy-${VERSION_NUM}-1.${ARCH_RPM}.rpm"
            TEMP_RPM=$(mktemp --suffix=.rpm)
            printf "%b\n" "${YELLOW}Downloading $RPM_FILE...${RC}"
            curl -sL "$BASE_URL/$RPM_FILE" -o "$TEMP_RPM"
            "$ESCALATION_TOOL" "$PACKAGER" install -y "$TEMP_RPM"
            rm -f "$TEMP_RPM"
            printf "%b\n" "${GREEN}✓ Handy installed via .rpm${RC}"
            ;;

        zypper)
            # openSUSE — use .rpm
            RPM_FILE="Handy-${VERSION_NUM}-1.${ARCH_RPM}.rpm"
            TEMP_RPM=$(mktemp --suffix=.rpm)
            printf "%b\n" "${YELLOW}Downloading $RPM_FILE...${RC}"
            curl -sL "$BASE_URL/$RPM_FILE" -o "$TEMP_RPM"
            "$ESCALATION_TOOL" zypper install -y "$TEMP_RPM"
            rm -f "$TEMP_RPM"
            printf "%b\n" "${GREEN}✓ Handy installed via .rpm${RC}"
            ;;

        pacman)
            # Arch — handy-bin is in AUR (pre-built binary, v0.8.3-1, maintained)
            # Not in official repos. Use yay or paru, fallback to AppImage.
            if command -v yay > /dev/null 2>&1; then
                yay -S --needed --noconfirm handy-bin
                printf "%b\n" "${GREEN}✓ Handy installed from AUR (handy-bin) via yay${RC}"
            elif command -v paru > /dev/null 2>&1; then
                paru -S --needed --noconfirm handy-bin
                printf "%b\n" "${GREEN}✓ Handy installed from AUR (handy-bin) via paru${RC}"
            else
                printf "%b\n" "${YELLOW}No AUR helper found — installing via AppImage...${RC}"
                installAppImage "$BASE_URL"
            fi
            ;;

        *)
            # Fallback: AppImage for any other distro
            printf "%b\n" "${YELLOW}Unknown package manager ($PACKAGER) — installing via AppImage...${RC}"
            installAppImage "$BASE_URL"
            ;;
    esac
}

installAppImage() {
    _base_url="$1"
    AI_FILE="Handy_${VERSION_NUM}_${ARCH_AI}.AppImage"

    mkdir -p "$HANDY_INSTALL_DIR" "$HOME/.local/bin"

    DEST="$HANDY_INSTALL_DIR/$AI_FILE"
    printf "%b\n" "${YELLOW}Downloading $AI_FILE...${RC}"
    curl -sL "$_base_url/$AI_FILE" -o "$DEST"
    chmod +x "$DEST"

    # Symlink to ~/.local/bin/handy so it's in PATH
    ln -sf "$DEST" "$HANDY_BIN"

    # Install AppImage desktop integration (icon + .desktop entry)
    if command -v appimaged > /dev/null 2>&1; then
        appimaged "$DEST" 2>/dev/null || true
    else
        # Create a minimal .desktop entry manually
        mkdir -p "$HOME/.local/share/applications"
        cat > "$HOME/.local/share/applications/handy.desktop" << EOF
[Desktop Entry]
Type=Application
Name=Handy
Comment=Speech-to-text (handy.computer)
Exec=$DEST
Icon=audio-input-microphone
Categories=Utility;Accessibility;
StartupNotify=false
EOF
    fi

    printf "%b\n" "${GREEN}✓ Handy installed as AppImage at $DEST${RC}"
    printf "%b\n" "${CYAN}  Symlinked to: $HANDY_BIN${RC}"
}

# ── Auto-start silently after login ───────────────────────────────────────────
# Handy runs in the background listening for its hotkey — no window on launch.
#
# ~/.xprofile   → sourced by LightDM's /etc/lightdm/Xsession before the WM.
#                 Primary path for DWM + LightDM.
# ~/.config/autostart/handy.desktop → XDG autostart fallback, processed by
#                 `dex -a` in dwm-jangir's autostart.sh (covers startx too).

setupAutostart() {
    printf "%b\n" "${YELLOW}Configuring Handy to auto-start silently after login...${RC}"

    # Resolve the handy binary or AppImage path
    if command -v handy > /dev/null 2>&1; then
        HANDY_EXEC="handy"
    elif [ -f "$HANDY_BIN" ]; then
        HANDY_EXEC="$HANDY_BIN"
    else
        # Native .deb/.rpm installs the binary as 'handy' but may need full path
        HANDY_EXEC="handy"
    fi

    # ── XDG autostart (dex -a / startx fallback) ──────────────────────────────
    AUTOSTART_DIR="$HOME/.config/autostart"
    DESKTOP_FILE="$AUTOSTART_DIR/handy-autostart.desktop"

    mkdir -p "$AUTOSTART_DIR"

    if [ -f "$DESKTOP_FILE" ]; then
        printf "%b\n" "${GREEN}✓ XDG autostart entry already exists${RC}"
    else
        cat > "$DESKTOP_FILE" << EOF
[Desktop Entry]
Type=Application
Name=Handy
Comment=Handy speech-to-text (background, no window)
Exec=$HANDY_EXEC --start-hidden
Icon=audio-input-microphone
Hidden=false
NoDisplay=false
X-GNOME-Autostart-enabled=true
EOF
        printf "%b\n" "${GREEN}✓ Created ~/.config/autostart/handy-autostart.desktop${RC}"
    fi
}

# ── Status ────────────────────────────────────────────────────────────────────

printStatus() {
    printf "%b\n" "${GREEN}========================================${RC}"
    printf "%b\n" "${GREEN}  Handy Setup Complete!${RC}"
    printf "%b\n" "${GREEN}========================================${RC}"
    printf "%b\n" "${CYAN}  App       : handy.computer (speech-to-text)${RC}"
    printf "%b\n" "${CYAN}  Auto-start: ~/.xprofile + ~/.config/autostart/${RC}"
    printf "%b\n" "${CYAN}  Open GUI  : handy${RC}"
    printf "%b\n" "${CYAN}  Logs out  : Handy starts silently on next login${RC}"
    printf "%b\n" "${GREEN}========================================${RC}"
}

# ── Main ──────────────────────────────────────────────────────────────────────

checkEnv
checkEscalationTool
installHandy
setupAutostart
printStatus
