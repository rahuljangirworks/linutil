#!/bin/sh -e

# Description: Install libinput-gestures (touchpad multi-finger gesture support)
#              and configure it to start silently after login.
#              Adds the user to the 'input' group (required to read /dev/input/*).
# Rerunnable:  Yes - skips completed steps

. ../../common-script.sh

installLibinputGestures() {
    if command -v libinput-gestures > /dev/null 2>&1; then
        printf "%b\n" "${GREEN}✓ libinput-gestures already installed${RC}"
        return 0
    fi

    printf "%b\n" "${YELLOW}Installing libinput-gestures...${RC}"
    case "$PACKAGER" in
        pacman)
            # AUR only — 101 votes, actively maintained (v2.81)
            if command -v yay > /dev/null 2>&1; then
                yay -S --needed --noconfirm libinput-gestures
                printf "%b\n" "${GREEN}✓ libinput-gestures installed from AUR (yay)${RC}"
            elif command -v paru > /dev/null 2>&1; then
                paru -S --needed --noconfirm libinput-gestures
                printf "%b\n" "${GREEN}✓ libinput-gestures installed from AUR (paru)${RC}"
            else
                printf "%b\n" "${RED}✗ No AUR helper found. Install yay or paru first.${RC}"
                exit 1
            fi
            ;;
        apt-get|nala)
            "$ESCALATION_TOOL" "$PACKAGER" install -y libinput-gestures
            ;;
        dnf|yum)
            "$ESCALATION_TOOL" "$PACKAGER" install -y libinput-gestures
            ;;
        *)
            printf "%b\n" "${YELLOW}→ libinput-gestures not available for $PACKAGER — skipping install${RC}"
            return 0
            ;;
    esac
}

configureInputGroup() {
    # libinput-gestures needs read access to /dev/input/* events
    if groups "$USER" | grep -qw input 2>/dev/null; then
        printf "%b\n" "${GREEN}✓ $USER already in 'input' group${RC}"
    else
        printf "%b\n" "${YELLOW}Adding $USER to 'input' group...${RC}"
        "$ESCALATION_TOOL" usermod -aG input "$USER"
        printf "%b\n" "${YELLOW}⚠ Group change takes effect on next login${RC}"
    fi
}

setupAutostart() {
    printf "%b\n" "${YELLOW}Configuring libinput-gestures autostart...${RC}"

    # Register via libinput-gestures-setup if available (creates its own XDG entry)
    if command -v libinput-gestures-setup > /dev/null 2>&1; then
        libinput-gestures-setup autostart 2>/dev/null && \
            printf "%b\n" "${GREEN}✓ libinput-gestures-setup autostart registered${RC}" || true
    fi

    # ── XDG autostart (dex -a / startx fallback) ──────────────────────────────
    DESKTOP_FILE="$HOME/.config/autostart/libinput-gestures.desktop"
    mkdir -p "$HOME/.config/autostart"
    if [ -f "$DESKTOP_FILE" ]; then
        printf "%b\n" "${GREEN}✓ XDG autostart entry already exists${RC}"
    else
        cat > "$DESKTOP_FILE" << 'EOF'
[Desktop Entry]
Type=Application
Name=Libinput Gestures
Comment=Touchpad multi-finger gesture support
Exec=libinput-gestures
Icon=input-touchpad
Hidden=false
NoDisplay=false
X-GNOME-Autostart-enabled=true
EOF
        printf "%b\n" "${GREEN}✓ Created ~/.config/autostart/libinput-gestures.desktop${RC}"
    fi
}

printStatus() {
    printf "%b\n" "${GREEN}========================================${RC}"
    printf "%b\n" "${GREEN}  libinput-gestures Setup Complete!${RC}"
    printf "%b\n" "${GREEN}========================================${RC}"
    printf "%b\n" "${CYAN}  Gesture support : libinput-gestures${RC}"
    printf "%b\n" "${CYAN}  Config file     : ~/.config/libinput-gestures.conf${RC}"
    printf "%b\n" "${CYAN}  Auto-start      : ~/.xprofile + ~/.config/autostart/${RC}"
    if ! groups "$USER" | grep -qw input 2>/dev/null; then
        printf "%b\n" "${YELLOW}  ⚠ Log out and back in — 'input' group needed for gestures${RC}"
    fi
    printf "%b\n" "${GREEN}========================================${RC}"
}

checkEnv
checkEscalationTool
installLibinputGestures
configureInputGroup
setupAutostart
printStatus
