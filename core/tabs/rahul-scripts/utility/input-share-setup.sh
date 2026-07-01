#!/bin/sh -e

# Description: Install Input Leap or Barrier for keyboard/mouse sharing and
#              print server/client setup guidance.
# Rerunnable:  Yes - package installs are skipped by package managers

. ../../common-script.sh

APP_CHOICE=""
APP_NAME=""
APP_PACKAGE=""
APP_COMMAND=""
ROLE_CHOICE=""

chooseApp() {
    printf "%b\n" "${GREEN}========================================${RC}"
    printf "%b\n" "${GREEN}  Keyboard & Mouse Sharing Setup${RC}"
    printf "%b\n" "${GREEN}========================================${RC}"
    printf "%b\n" "${CYAN}  1) Input Leap  - maintained Barrier fork (recommended)${RC}"
    printf "%b\n" "${CYAN}  2) Barrier     - older Synergy v1 fork, broad compatibility${RC}"
    printf "%b\n" "${CYAN}  3) Abort${RC}"
    printf "%b" "${YELLOW}Choose app [1-3, default 1]: ${RC}"
    read -r APP_CHOICE

    case "${APP_CHOICE:-1}" in
        1)
            APP_NAME="Input Leap"
            APP_PACKAGE="input-leap"
            APP_COMMAND="input-leap"
            ;;
        2)
            APP_NAME="Barrier"
            APP_PACKAGE="barrier"
            APP_COMMAND="barrier"
            ;;
        3)
            printf "%b\n" "${YELLOW}Aborted.${RC}"
            exit 0
            ;;
        *)
            printf "%b\n" "${RED}Invalid app choice.${RC}"
            exit 1
            ;;
    esac
}

chooseRole() {
    printf "%b\n" "${GREEN}========================================${RC}"
    printf "%b\n" "${GREEN}  Server or Client?${RC}"
    printf "%b\n" "${GREEN}========================================${RC}"
    printf "%b\n" "${CYAN}  1) Server - this computer has the keyboard and mouse${RC}"
    printf "%b\n" "${CYAN}  2) Client - this computer is controlled by another computer${RC}"
    printf "%b\n" "${CYAN}  3) Decide later in the GUI${RC}"
    printf "%b" "${YELLOW}Choose role [1-3, default 1]: ${RC}"
    read -r ROLE_CHOICE

    case "${ROLE_CHOICE:-1}" in
        1|2|3) ;;
        *)
            printf "%b\n" "${RED}Invalid role choice.${RC}"
            exit 1
            ;;
    esac
}

isInstalled() {
    command -v "$APP_COMMAND" > /dev/null 2>&1 && return 0

    case "$PACKAGER" in
        pacman)
            pacman -Qq "$APP_PACKAGE" > /dev/null 2>&1
            ;;
        apt-get|nala)
            dpkg -s "$APP_PACKAGE" > /dev/null 2>&1
            ;;
        dnf|yum|zypper)
            rpm -q "$APP_PACKAGE" > /dev/null 2>&1
            ;;
        apk)
            apk info -e "$APP_PACKAGE" > /dev/null 2>&1
            ;;
        xbps-install)
            xbps-query "$APP_PACKAGE" > /dev/null 2>&1
            ;;
        eopkg)
            eopkg info "$APP_PACKAGE" > /dev/null 2>&1
            ;;
        *)
            return 1
            ;;
    esac
}

installWithPackageManager() {
    case "$PACKAGER" in
        pacman)
            "$ESCALATION_TOOL" pacman -S --needed --noconfirm "$APP_PACKAGE"
            ;;
        apt-get|nala)
            "$ESCALATION_TOOL" "$PACKAGER" update
            "$ESCALATION_TOOL" "$PACKAGER" install -y "$APP_PACKAGE"
            ;;
        dnf|yum)
            "$ESCALATION_TOOL" "$PACKAGER" install -y "$APP_PACKAGE"
            ;;
        zypper)
            "$ESCALATION_TOOL" zypper install -y "$APP_PACKAGE"
            ;;
        apk)
            "$ESCALATION_TOOL" apk add "$APP_PACKAGE"
            ;;
        xbps-install)
            "$ESCALATION_TOOL" xbps-install -Sy "$APP_PACKAGE"
            ;;
        eopkg)
            "$ESCALATION_TOOL" eopkg install -y "$APP_PACKAGE"
            ;;
        *)
            printf "%b\n" "${RED}Unsupported package manager: $PACKAGER${RC}"
            exit 1
            ;;
    esac
}

installSelectedApp() {
    if isInstalled; then
        printf "%b\n" "${GREEN}✓ $APP_NAME already installed${RC}"
        return 0
    fi

    printf "%b\n" "${YELLOW}Installing $APP_NAME...${RC}"
    if installWithPackageManager; then
        printf "%b\n" "${GREEN}✓ $APP_NAME installed${RC}"
        return 0
    fi

    if [ "$APP_PACKAGE" = "input-leap" ]; then
        printf "%b\n" "${YELLOW}Input Leap was not available from $PACKAGER. Trying Barrier...${RC}"
        APP_NAME="Barrier"
        APP_PACKAGE="barrier"
        APP_COMMAND="barrier"
        installWithPackageManager
        printf "%b\n" "${GREEN}✓ Barrier installed${RC}"
        return 0
    fi

    printf "%b\n" "${RED}✗ Could not install $APP_NAME with $PACKAGER${RC}"
    exit 1
}

openServerFirewall() {
    if [ "$ROLE_CHOICE" != "1" ]; then
        return 0
    fi

    printf "%b\n" "${YELLOW}Checking firewall for server mode...${RC}"
    if command -v ufw > /dev/null 2>&1 && "$ESCALATION_TOOL" ufw status 2>/dev/null | grep -q "Status: active"; then
        "$ESCALATION_TOOL" ufw allow 24800/tcp
        printf "%b\n" "${GREEN}✓ Opened TCP 24800 in UFW${RC}"
    elif command -v firewall-cmd > /dev/null 2>&1 && "$ESCALATION_TOOL" firewall-cmd --state > /dev/null 2>&1; then
        "$ESCALATION_TOOL" firewall-cmd --permanent --add-port=24800/tcp
        "$ESCALATION_TOOL" firewall-cmd --reload
        printf "%b\n" "${GREEN}✓ Opened TCP 24800 in firewalld${RC}"
    else
        printf "%b\n" "${CYAN}No active UFW/firewalld detected. If another firewall is used, allow TCP 24800 on the server.${RC}"
    fi
}

printStatus() {
    printf "%b\n" "${GREEN}========================================${RC}"
    printf "%b\n" "${GREEN}  $APP_NAME Setup Complete${RC}"
    printf "%b\n" "${GREEN}========================================${RC}"
    printf "%b\n" "${CYAN}  Open GUI : $APP_COMMAND${RC}"
    printf "%b\n" "${CYAN}  Port     : TCP 24800${RC}"

    case "$ROLE_CHOICE" in
        1)
            printf "%b\n" "${CYAN}  Role     : Server${RC}"
            printf "%b\n" "${CYAN}  Meaning  : This machine owns the keyboard and mouse.${RC}"
            printf "%b\n" "${CYAN}  Next     : Open $APP_NAME, choose Server, place client screens around this screen, then Apply/Start.${RC}"
            ;;
        2)
            printf "%b\n" "${CYAN}  Role     : Client${RC}"
            printf "%b\n" "${CYAN}  Meaning  : This machine is controlled by the server machine.${RC}"
            printf "%b\n" "${CYAN}  Next     : Open $APP_NAME, choose Client, enter the server IP/hostname, then Apply/Start.${RC}"
            ;;
        3)
            printf "%b\n" "${CYAN}  Role     : Decide later in the GUI.${RC}"
            ;;
    esac

    printf "%b\n" "${CYAN}  Tip      : Install the same app on both computers for the smoothest setup.${RC}"
    printf "%b\n" "${GREEN}========================================${RC}"
}

checkArch
checkEscalationTool
checkCommandRequirements "groups $ESCALATION_TOOL"
checkPackageManager 'nala apt-get dnf pacman zypper apk xbps-install eopkg'
checkCurrentDirectoryWritable
checkSuperUser
checkDistro
chooseApp
chooseRole
installSelectedApp
openServerFirewall
printStatus
