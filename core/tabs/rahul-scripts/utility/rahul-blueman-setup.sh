#!/bin/sh -e

# Description: Install Blueman Bluetooth manager and start blueman-applet
#              silently in the background after login (LightDM + startx).
# Rerunnable:  Yes - skips completed steps

. ../../common-script.sh

installBlueman() {
    if command -v blueman-applet > /dev/null 2>&1; then
        printf "%b\n" "${GREEN}✓ blueman already installed${RC}"
        return 0
    fi

    printf "%b\n" "${YELLOW}Installing blueman...${RC}"
    case "$PACKAGER" in
        pacman)
            # Official extra repo (2.4.6)
            "$ESCALATION_TOOL" pacman -S --needed --noconfirm blueman
            ;;
        apt-get|nala)
            "$ESCALATION_TOOL" "$PACKAGER" install -y blueman
            ;;
        dnf|yum)
            "$ESCALATION_TOOL" "$PACKAGER" install -y blueman
            ;;
        zypper)
            "$ESCALATION_TOOL" zypper install -y blueman
            ;;
        *)
            printf "%b\n" "${RED}✗ Unsupported package manager: $PACKAGER${RC}"
            exit 1
            ;;
    esac
    printf "%b\n" "${GREEN}✓ blueman installed${RC}"
}

setupAutostart() {
    printf "%b\n" "${YELLOW}Configuring blueman-applet autostart...${RC}"

    # The package manager automatically installs /etc/xdg/autostart/blueman.desktop
    # dex -a will automatically pick it up, so no custom .desktop file is needed.
}

printStatus() {
    printf "%b\n" "${GREEN}========================================${RC}"
    printf "%b\n" "${GREEN}  Blueman Setup Complete!${RC}"
    printf "%b\n" "${GREEN}========================================${RC}"
    printf "%b\n" "${CYAN}  Tray app  : blueman-applet (Bluetooth)${RC}"
    printf "%b\n" "${CYAN}  Auto-start: ~/.xprofile + ~/.config/autostart/${RC}"
    printf "%b\n" "${CYAN}  Open GUI  : blueman-manager${RC}"
    printf "%b\n" "${GREEN}========================================${RC}"
}

checkEnv
checkEscalationTool
installBlueman
setupAutostart
printStatus
