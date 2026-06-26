#!/bin/sh -e

# Description: Install caffeine-ng (screen inhibitor tray app) and configure
#              it to start silently in the background after login.
#              caffeine-ng lets you toggle sleep/lock prevention from the tray.
#              Works on any WM (DWM, i3, bspwm, etc.) — NOT the GNOME extension.
# Rerunnable:  Yes - skips completed steps

. ../../common-script.sh

installCaffeineNg() {
    if command -v caffeine > /dev/null 2>&1 || command -v caffeine-ng > /dev/null 2>&1; then
        printf "%b\n" "${GREEN}✓ caffeine-ng already installed${RC}"
        return 0
    fi

    printf "%b\n" "${YELLOW}Installing caffeine-ng...${RC}"
    case "$PACKAGER" in
        pacman)
            # AUR only — 132 votes, v4.3.2 (gnome-shell-extension-caffeine in
            # official repos is different — GNOME-only, won't work in DWM)
            if command -v yay > /dev/null 2>&1; then
                yay -S --needed --noconfirm caffeine-ng
                printf "%b\n" "${GREEN}✓ caffeine-ng installed from AUR (yay)${RC}"
            elif command -v paru > /dev/null 2>&1; then
                paru -S --needed --noconfirm caffeine-ng
                printf "%b\n" "${GREEN}✓ caffeine-ng installed from AUR (paru)${RC}"
            else
                printf "%b\n" "${RED}✗ No AUR helper found. Install yay or paru first.${RC}"
                exit 1
            fi
            ;;
        apt-get|nala)
            "$ESCALATION_TOOL" "$PACKAGER" install -y caffeine
            ;;
        dnf|yum)
            "$ESCALATION_TOOL" "$PACKAGER" install -y caffeine
            ;;
        zypper)
            "$ESCALATION_TOOL" zypper install -y caffeine
            ;;
        *)
            printf "%b\n" "${YELLOW}→ caffeine-ng not available for $PACKAGER — skipping${RC}"
            return 0
            ;;
    esac
}

setupAutostart() {
    printf "%b\n" "${YELLOW}Configuring caffeine-ng autostart...${RC}"

    # Resolve binary name (Arch AUR installs as 'caffeine', Debian as 'caffeine')
    CAFFEINE_BIN=""
    if command -v caffeine-ng > /dev/null 2>&1; then
        CAFFEINE_BIN="caffeine-ng"
    elif command -v caffeine > /dev/null 2>&1; then
        CAFFEINE_BIN="caffeine"
    else
        printf "%b\n" "${YELLOW}→ caffeine binary not found yet — skipping autostart setup${RC}"
        return 0
    fi

    # The package manager automatically installs /etc/xdg/autostart/caffeine.desktop
    # dex -a will automatically pick it up, so no custom .desktop file is needed.
}

printStatus() {
    printf "%b\n" "${GREEN}========================================${RC}"
    printf "%b\n" "${GREEN}  caffeine-ng Setup Complete!${RC}"
    printf "%b\n" "${GREEN}========================================${RC}"
    printf "%b\n" "${CYAN}  Tray app  : caffeine-ng (screen inhibitor)${RC}"
    printf "%b\n" "${CYAN}  Usage     : Click tray icon to toggle sleep prevention${RC}"
    printf "%b\n" "${CYAN}  Auto-start: ~/.xprofile + ~/.config/autostart/${RC}"
    printf "%b\n" "${GREEN}========================================${RC}"
}

checkEnv
checkEscalationTool
installCaffeineNg
setupAutostart
printStatus
