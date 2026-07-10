#!/bin/sh -e

# Description: Install RustDesk remote desktop and configure it to run
#              silently in the background after login.
# Rerunnable: Yes - skips completed steps

. ../../common-script.sh

# ── Install RustDesk ──────────────────────────────────────────────────────────

RUSTDESK_API_URL="https://api.github.com/repos/rustdesk/rustdesk/releases/latest"
RUSTDESK_INSTALL_KIND=""
RUSTDESK_LAUNCH_CMD="rustdesk"
RUSTDESK_TRAY_CMD="rustdesk --tray"
RUSTDESK_SESSION_TYPE="${XDG_SESSION_TYPE:-unknown}"
RUSTDESK_DISPLAY_MANAGER="unknown"
RUSTDESK_XPROFILE_STATUS="not checked"

detectRustDeskInstall() {
    if command -v rustdesk > /dev/null 2>&1; then
        RUSTDESK_INSTALL_KIND="native"
        RUSTDESK_LAUNCH_CMD="rustdesk"
        RUSTDESK_TRAY_CMD="rustdesk --tray"
        return 0
    fi

    if command -v flatpak > /dev/null 2>&1 && flatpak info com.rustdesk.RustDesk > /dev/null 2>&1; then
        RUSTDESK_INSTALL_KIND="flatpak"
        RUSTDESK_LAUNCH_CMD="flatpak run com.rustdesk.RustDesk"
        RUSTDESK_TRAY_CMD="flatpak run com.rustdesk.RustDesk --tray"
        return 0
    fi

    return 1
}

releaseAssetUrl() {
    local include_pattern="$1"
    local exclude_pattern="${2:-__rustdesk_never_match__}"

    curl -fsSL "$RUSTDESK_API_URL" |
        sed -n 's/.*"browser_download_url"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' |
        grep -E "$include_pattern" |
        grep -Ev "$exclude_pattern" |
        head -n 1
}

downloadAndInstall() {
    local url="$1"
    local suffix="$2"
    local temp_pkg

    if [ -z "$url" ]; then
        return 1
    fi

    temp_pkg=$(mktemp "${TMPDIR:-/tmp}/rustdesk.XXXXXX.$suffix")
    printf "%b\n" "${YELLOW}Downloading RustDesk package...${RC}"

    if ! curl -fL "$url" -o "$temp_pkg"; then
        rm -f "$temp_pkg"
        return 1
    fi

    case "$suffix" in
        deb)
            if ! "$ESCALATION_TOOL" apt-get update -qq; then
                rm -f "$temp_pkg"
                return 1
            fi
            if ! "$ESCALATION_TOOL" apt-get install -y "$temp_pkg"; then
                rm -f "$temp_pkg"
                return 1
            fi
            ;;
        rpm)
            if ! "$ESCALATION_TOOL" "$PACKAGER" install -y "$temp_pkg"; then
                rm -f "$temp_pkg"
                return 1
            fi
            ;;
        pkg.tar.zst)
            if ! "$ESCALATION_TOOL" pacman -U --needed --noconfirm "$temp_pkg"; then
                rm -f "$temp_pkg"
                return 1
            fi
            ;;
        *)
            rm -f "$temp_pkg"
            return 1
            ;;
    esac

    rm -f "$temp_pkg"
    return 0
}

installRustDesk() {
    if detectRustDeskInstall; then
        printf "%b\n" "${GREEN}✓ RustDesk already installed${RC}"
        return 0
    fi

    printf "%b\n" "${YELLOW}Installing RustDesk...${RC}"

    case "$PACKAGER" in
        pacman)
            LATEST_URL=$(releaseAssetUrl "rustdesk-.*-${ARCH}\\.pkg\\.tar\\.zst$")
            if downloadAndInstall "$LATEST_URL" "pkg.tar.zst"; then
                printf "%b\n" "${GREEN}✓ RustDesk installed from upstream Arch package${RC}"
            else
                printf "%b\n" "${YELLOW}Could not install native Arch package, trying Flatpak...${RC}"
                installFlatpak
            fi
            ;;
        apt-get|nala)
            LATEST_URL=$(releaseAssetUrl "rustdesk-.*-${ARCH}\\.deb$")
            if downloadAndInstall "$LATEST_URL" "deb"; then
                printf "%b\n" "${GREEN}✓ RustDesk installed from upstream Debian package${RC}"
            else
                printf "%b\n" "${YELLOW}Could not install native Debian package, trying Flatpak...${RC}"
                installFlatpak
            fi
            ;;
        dnf|yum)
            printf "%b\n" "${CYAN}Best method for Fedora/RHEL: install the official RustDesk RPM package.${RC}"
            LATEST_URL=$(releaseAssetUrl "rustdesk-.*\\.${ARCH}\\.rpm$" "suse")
            if downloadAndInstall "$LATEST_URL" "rpm"; then
                printf "%b\n" "${GREEN}✓ RustDesk installed from official RPM package${RC}"
            else
                printf "%b\n" "${YELLOW}Could not install official RPM package, trying Flatpak...${RC}"
                installFlatpak
            fi
            ;;
        zypper)
            LATEST_URL=$(releaseAssetUrl "rustdesk-.*\\.${ARCH}-suse\\.rpm$")
            if downloadAndInstall "$LATEST_URL" "rpm"; then
                printf "%b\n" "${GREEN}✓ RustDesk installed from upstream openSUSE package${RC}"
            else
                printf "%b\n" "${YELLOW}Could not install native openSUSE package, trying Flatpak...${RC}"
                installFlatpak
            fi
            ;;
        *)
            printf "%b\n" "${YELLOW}No native RustDesk package path for $PACKAGER, trying Flatpak...${RC}"
            installFlatpak
            ;;
    esac

    if detectRustDeskInstall; then
        return 0
    fi

    printf "%b\n" "${RED}✗ RustDesk install finished, but no runnable RustDesk command was found.${RC}"
    exit 1
}

installFlatpak() {
    checkFlatpak
    flatpak install -y flathub com.rustdesk.RustDesk
    RUSTDESK_INSTALL_KIND="flatpak"
    RUSTDESK_LAUNCH_CMD="flatpak run com.rustdesk.RustDesk"
    RUSTDESK_TRAY_CMD="flatpak run com.rustdesk.RustDesk --tray"
    printf "%b\n" "${GREEN}✓ RustDesk installed via Flatpak${RC}"
}

# ── Enable system service (boot persistence) ──────────────────────────────────
# The rustdesk.service daemon runs as root, independently of any X session.
# This is what keeps RustDesk accepting remote connections across reboots.

enableService() {
    if [ "$RUSTDESK_INSTALL_KIND" = "flatpak" ]; then
        printf "%b\n" "${YELLOW}→ Flatpak install detected; no system rustdesk.service is available.${RC}"
        return 0
    fi

    if ! command -v systemctl > /dev/null 2>&1; then
        printf "%b\n" "${YELLOW}→ systemctl not found; skipping RustDesk system service.${RC}"
        return 0
    fi

    # Native package provides rustdesk.service; Flatpak installs do not.
    if ! systemctl list-unit-files rustdesk.service > /dev/null 2>&1; then
        printf "%b\n" "${YELLOW}→ No rustdesk.service found; RustDesk will start after user login only.${RC}"
        return 0
    fi

    if systemctl is-active --quiet rustdesk 2>/dev/null; then
        printf "%b\n" "${GREEN}✓ RustDesk service already running${RC}"
        return 0
    fi

    printf "%b\n" "${YELLOW}Enabling RustDesk service on boot...${RC}"
    "$ESCALATION_TOOL" systemctl enable --now rustdesk
    printf "%b\n" "${GREEN}✓ RustDesk service enabled and started${RC}"
}

# ── Auto-start silently after login ───────────────────────────────────────────
# Strategy:
#   ~/.xprofile  — managed only when this looks like an X11/LightDM/startx
#                  session path.
#   ~/.config/autostart/rustdesk.desktop — XDG autostart used by common
#                  desktop sessions and by dex in dwm-rahul.
#
# `rustdesk --tray` starts the tray icon only — no main window shown.

detectLoginSession() {
    RUSTDESK_SESSION_TYPE="${XDG_SESSION_TYPE:-unknown}"
    RUSTDESK_DISPLAY_MANAGER="unknown"

    if [ -L /etc/systemd/system/display-manager.service ]; then
        RUSTDESK_DISPLAY_MANAGER=$(basename "$(readlink /etc/systemd/system/display-manager.service)" .service)
    elif command -v pgrep > /dev/null 2>&1; then
        if pgrep -x lightdm > /dev/null 2>&1; then
            RUSTDESK_DISPLAY_MANAGER="lightdm"
        elif pgrep -x gdm > /dev/null 2>&1 || pgrep -x gdm3 > /dev/null 2>&1; then
            RUSTDESK_DISPLAY_MANAGER="gdm"
        elif pgrep -x sddm > /dev/null 2>&1; then
            RUSTDESK_DISPLAY_MANAGER="sddm"
        fi
    fi

    printf "%b\n" "${CYAN}Detected session: ${RUSTDESK_SESSION_TYPE}, display manager: ${RUSTDESK_DISPLAY_MANAGER}${RC}"
}

shouldUseXprofile() {
    if [ "$RUSTDESK_SESSION_TYPE" = "x11" ]; then
        return 0
    fi

    if [ "$RUSTDESK_DISPLAY_MANAGER" = "lightdm" ]; then
        return 0
    fi

    if [ -f "$HOME/.xinitrc" ]; then
        return 0
    fi

    if command -v pgrep > /dev/null 2>&1 && pgrep -x Xorg > /dev/null 2>&1; then
        return 0
    fi

    return 1
}

writeXprofileAutostart() {
    XPROFILE="$HOME/.xprofile"
    XPROFILE_MARKER="# rustdesk autostart"
    XPROFILE_TMP=""

    if [ -f "$XPROFILE" ] && grep -q "$XPROFILE_MARKER" "$XPROFILE" 2>/dev/null; then
        XPROFILE_TMP=$(mktemp)
        awk -v marker="$XPROFILE_MARKER" '
            $0 == marker { skip_next = 1; next }
            skip_next { skip_next = 0; next }
            { print }
        ' "$XPROFILE" > "$XPROFILE_TMP"
        mv "$XPROFILE_TMP" "$XPROFILE"
    fi

    printf "\n%s\n%s &\n" "$XPROFILE_MARKER" "$RUSTDESK_TRAY_CMD" >> "$XPROFILE"
    chmod +x "$XPROFILE"
    RUSTDESK_XPROFILE_STATUS="enabled"
    printf "%b\n" "${GREEN}✓ Added RustDesk to ~/.xprofile${RC}"
}

writeXdgAutostart() {
    AUTOSTART_DIR="$HOME/.config/autostart"
    DESKTOP_FILE="$AUTOSTART_DIR/rustdesk-tray.desktop"

    mkdir -p "$AUTOSTART_DIR"

    cat > "$DESKTOP_FILE" << EOF
[Desktop Entry]
Type=Application
Name=RustDesk
Comment=RustDesk remote desktop (tray, no window)
Exec=$RUSTDESK_TRAY_CMD
Icon=rustdesk
Hidden=false
NoDisplay=false
X-GNOME-Autostart-enabled=true
EOF
    printf "%b\n" "${GREEN}✓ Wrote ~/.config/autostart/rustdesk-tray.desktop${RC}"
}

setupAutostart() {
    printf "%b\n" "${YELLOW}Configuring RustDesk to auto-start silently after login...${RC}"
    detectLoginSession

    if shouldUseXprofile; then
        writeXprofileAutostart
    else
        RUSTDESK_XPROFILE_STATUS="skipped (not an X11/LightDM/startx session)"
        printf "%b\n" "${YELLOW}→ Skipping ~/.xprofile; XDG autostart will handle this session type.${RC}"
    fi

    writeXdgAutostart
}

# ── Status ────────────────────────────────────────────────────────────────────

printStatus() {
    printf "%b\n" "${GREEN}========================================${RC}"
    printf "%b\n" "${GREEN}  RustDesk Setup Complete!${RC}"
    printf "%b\n" "${GREEN}========================================${RC}"

    if command -v rustdesk > /dev/null 2>&1; then
        RUSTDESK_ID=$(rustdesk --get-id 2>/dev/null || echo "(start rustdesk to see ID)")
        printf "%b\n" "${CYAN}  Your RustDesk ID : $RUSTDESK_ID${RC}"
    fi

    printf "%b\n" "${CYAN}  Install type     : ${RUSTDESK_INSTALL_KIND:-unknown}${RC}"
    printf "%b\n" "${CYAN}  Session          : ${RUSTDESK_SESSION_TYPE} / ${RUSTDESK_DISPLAY_MANAGER}${RC}"
    printf "%b\n" "${CYAN}  ~/.xprofile      : $RUSTDESK_XPROFILE_STATUS${RC}"
    printf "%b\n" "${CYAN}  XDG autostart    : ~/.config/autostart/rustdesk-tray.desktop${RC}"
    if [ "$RUSTDESK_INSTALL_KIND" = "native" ]; then
        printf "%b\n" "${CYAN}  Boot service     : rustdesk.service when provided by package${RC}"
    else
        printf "%b\n" "${CYAN}  Boot service     : unavailable for Flatpak install${RC}"
    fi
    printf "%b\n" "${CYAN}  Open GUI         : $RUSTDESK_LAUNCH_CMD${RC}"
    printf "%b\n" "${YELLOW}  Note             : login-screen access still needs an X11 display manager session.${RC}"
    printf "%b\n" "${GREEN}========================================${RC}"
}

# ── Main ──────────────────────────────────────────────────────────────────────

checkEnv
checkEscalationTool
installRustDesk
enableService
setupAutostart
printStatus
