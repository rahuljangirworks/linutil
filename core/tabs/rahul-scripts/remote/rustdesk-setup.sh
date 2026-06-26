#!/bin/sh -e

# Description: Install RustDesk remote desktop and configure it to run
#              silently in the background after login (LightDM + startx).
# Rerunnable: Yes - skips completed steps

. ../../common-script.sh

# ── Install RustDesk ──────────────────────────────────────────────────────────

installRustDesk() {
    if command -v rustdesk > /dev/null 2>&1; then
        printf "%b\n" "${GREEN}✓ RustDesk already installed${RC}"
        return 0
    fi

    printf "%b\n" "${YELLOW}Installing RustDesk...${RC}"

    case "$PACKAGER" in
        pacman)
            # Official repos first, then AUR helpers, then Flatpak
            if "$ESCALATION_TOOL" "$PACKAGER" -S --needed --noconfirm rustdesk 2>/dev/null; then
                printf "%b\n" "${GREEN}✓ RustDesk installed from official repos${RC}"
            elif command -v yay > /dev/null 2>&1; then
                yay -S --needed --noconfirm rustdesk
                printf "%b\n" "${GREEN}✓ RustDesk installed from AUR (yay)${RC}"
            elif command -v paru > /dev/null 2>&1; then
                paru -S --needed --noconfirm rustdesk
                printf "%b\n" "${GREEN}✓ RustDesk installed from AUR (paru)${RC}"
            else
                installFlatpak
            fi
            ;;
        apt-get|nala)
            LATEST_URL=$(curl -s https://api.github.com/repos/rustdesk/rustdesk/releases/latest \
                | grep "browser_download_url.*x86_64.*deb" | head -1 | cut -d '"' -f 4)
            if [ -n "$LATEST_URL" ]; then
                TEMP_DEB=$(mktemp --suffix=.deb)
                printf "%b\n" "${YELLOW}Downloading RustDesk...${RC}"
                curl -sL "$LATEST_URL" -o "$TEMP_DEB"
                "$ESCALATION_TOOL" apt-get update -qq
                "$ESCALATION_TOOL" apt-get install -y "$TEMP_DEB"
                rm -f "$TEMP_DEB"
                printf "%b\n" "${GREEN}✓ RustDesk installed${RC}"
            else
                printf "%b\n" "${YELLOW}Could not fetch .deb, trying Flatpak...${RC}"
                installFlatpak
            fi
            ;;
        dnf|yum)
            LATEST_URL=$(curl -s https://api.github.com/repos/rustdesk/rustdesk/releases/latest \
                | grep "browser_download_url.*x86_64.*rpm" | grep -v suse | head -1 | cut -d '"' -f 4)
            if [ -n "$LATEST_URL" ]; then
                TEMP_RPM=$(mktemp --suffix=.rpm)
                printf "%b\n" "${YELLOW}Downloading RustDesk...${RC}"
                curl -sL "$LATEST_URL" -o "$TEMP_RPM"
                "$ESCALATION_TOOL" "$PACKAGER" install -y "$TEMP_RPM"
                rm -f "$TEMP_RPM"
                printf "%b\n" "${GREEN}✓ RustDesk installed${RC}"
            else
                printf "%b\n" "${YELLOW}Could not fetch .rpm, trying Flatpak...${RC}"
                installFlatpak
            fi
            ;;
        zypper)
            LATEST_URL=$(curl -s https://api.github.com/repos/rustdesk/rustdesk/releases/latest \
                | grep "browser_download_url.*suse.*rpm" | head -1 | cut -d '"' -f 4)
            if [ -n "$LATEST_URL" ]; then
                TEMP_RPM=$(mktemp --suffix=.rpm)
                printf "%b\n" "${YELLOW}Downloading RustDesk...${RC}"
                curl -sL "$LATEST_URL" -o "$TEMP_RPM"
                "$ESCALATION_TOOL" "$PACKAGER" install -y "$TEMP_RPM"
                rm -f "$TEMP_RPM"
                printf "%b\n" "${GREEN}✓ RustDesk installed${RC}"
            else
                printf "%b\n" "${YELLOW}Could not fetch .rpm, trying Flatpak...${RC}"
                installFlatpak
            fi
            ;;
        *)
            installFlatpak
            ;;
    esac
}

installFlatpak() {
    if command -v flatpak > /dev/null 2>&1; then
        flatpak install -y flathub com.rustdesk.RustDesk
        printf "%b\n" "${GREEN}✓ RustDesk installed via Flatpak${RC}"
    else
        printf "%b\n" "${RED}✗ Flatpak not available. Install RustDesk manually:${RC}"
        printf "%b\n" "${CYAN}  https://github.com/rustdesk/rustdesk/releases${RC}"
        exit 1
    fi
}

# ── Enable system service (boot persistence) ──────────────────────────────────
# The rustdesk.service daemon runs as root, independently of any X session.
# This is what keeps RustDesk accepting remote connections across reboots.

enableService() {
    # Native package provides rustdesk.service; Flatpak installs do not.
    if ! systemctl list-unit-files rustdesk.service > /dev/null 2>&1; then
        printf "%b\n" "${YELLOW}→ No rustdesk.service found (Flatpak install — daemon managed by Flatpak)${RC}"
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
#   ~/.xprofile  — sourced by LightDM's /etc/lightdm/Xsession before the WM.
#                  This is the correct hook for LightDM sessions.
#   ~/.config/autostart/rustdesk.desktop — XDG autostart fallback, processed
#                  by `dex -a` in dwm-rahul's autostart.sh (covers startx path).
#
# `rustdesk --tray` starts the tray icon only — no main window shown.

setupAutostart() {
    printf "%b\n" "${YELLOW}Configuring RustDesk to auto-start silently after login...${RC}"

    # ── 1. ~/.xprofile (LightDM path) ────────────────────────────────────────
    XPROFILE="$HOME/.xprofile"
    XPROFILE_MARKER="# rustdesk autostart"

    if [ -f "$XPROFILE" ] && grep -q "$XPROFILE_MARKER" "$XPROFILE" 2>/dev/null; then
        printf "%b\n" "${GREEN}✓ ~/.xprofile already has RustDesk entry${RC}"
    else
        printf "\n%s\nrustdesk --tray &\n" "$XPROFILE_MARKER" >> "$XPROFILE"
        chmod +x "$XPROFILE"
        printf "%b\n" "${GREEN}✓ Added RustDesk to ~/.xprofile (LightDM)${RC}"
    fi

    # ── 2. XDG autostart .desktop (dex -a / startx fallback) ─────────────────
    AUTOSTART_DIR="$HOME/.config/autostart"
    DESKTOP_FILE="$AUTOSTART_DIR/rustdesk-tray.desktop"

    mkdir -p "$AUTOSTART_DIR"

    if [ -f "$DESKTOP_FILE" ]; then
        printf "%b\n" "${GREEN}✓ XDG autostart entry already exists${RC}"
    else
        cat > "$DESKTOP_FILE" << 'EOF'
[Desktop Entry]
Type=Application
Name=RustDesk
Comment=RustDesk remote desktop (tray, no window)
Exec=rustdesk --tray
Icon=rustdesk
Hidden=false
NoDisplay=false
X-GNOME-Autostart-enabled=true
EOF
        printf "%b\n" "${GREEN}✓ Created ~/.config/autostart/rustdesk-tray.desktop${RC}"
    fi
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

    printf "%b\n" "${CYAN}  Auto-start       : ~/.xprofile + ~/.config/autostart/${RC}"
    printf "%b\n" "${CYAN}  Boot service     : rustdesk.service (systemd)${RC}"
    printf "%b\n" "${CYAN}  Open GUI         : rustdesk${RC}"
    printf "%b\n" "${GREEN}========================================${RC}"
}

# ── Main ──────────────────────────────────────────────────────────────────────

checkEnv
checkEscalationTool
installRustDesk
enableService
setupAutostart
printStatus
