#!/bin/sh -e

# Description: Install GitHub Desktop Plus (up-to-date fork with Copilot, Bitbucket & GitLab support)
# Fork: pol-rivero/github-desktop-plus (v3.5.9+)
# Works on: Arch, Debian, Fedora, openSUSE

. ../common-script.sh

APP_NAME="GitHub Desktop Plus"
APP_VERSION="3.5.9.2"

clear 2>/dev/null || true
printf "%b\n" "${CYAN}=================================================================${RC}"
printf "%b\n" "${YELLOW}        $APP_NAME v${APP_VERSION} Installer                          ${RC}"
printf "%b\n" "${CYAN}=================================================================${RC}"
printf "%b\n" "${GREEN}  - Up-to-date fork of GitHub Desktop for Linux${RC}"
printf "%b\n" "${GREEN}  - Copilot commit message generation (v3.5+)${RC}"
printf "%b\n" "${GREEN}  - Bitbucket & GitLab integration${RC}"
printf "%b\n" "${GREEN}  - Latest features from upstream desktop/desktop${RC}"
printf "%b\n" "${CYAN}=================================================================${RC}"
echo ""

install_github_desktop_plus() {
    # Check if already installed (either old or new version)
    if command_exists github-desktop || command_exists github-desktop-plus || pacman -Q github-desktop-bin >/dev/null 2>&1 || pacman -Q github-desktop-plus-bin >/dev/null 2>&1; then
        # Get version from pacman if available, fallback to --version
        CURRENT_VER=$(pacman -Q github-desktop-bin 2>/dev/null | awk '{print $2}' || pacman -Q github-desktop-plus-bin 2>/dev/null | awk '{print $2}' || github-desktop --version 2>/dev/null || echo "unknown")
        printf "%b\n" "${GREEN}[✓] GitHub Desktop already installed — v$CURRENT_VER${RC}"
        printf "%b\n" "${YELLOW}[*] Checking if upgrade to Plus is needed...${RC}"

        # If on old version (< 3.5), offer upgrade
        case "$CURRENT_VER" in
            3.4.*|3.3.*|3.2.*|3.1.*|3.0.*|unknown)
                printf "%b\n" "${YELLOW}[~] Your version ($CURRENT_VER) is too old for Copilot.${RC}"
                printf "%b\n" "${YELLOW}    Copilot requires v3.4.19+ (GA in v3.5.0).${RC}"
                printf "%b\n" "${YELLOW}[*] Upgrading to GitHub Desktop Plus...${RC}"
                remove_old_version
                ;;
            *)
                printf "%b\n" "${GREEN}[✓] Version $CURRENT_VER supports Copilot — no action needed.${RC}"
                return 0
                ;;
        esac
    fi

    printf "%b\n" "${YELLOW}[*] Installing $APP_NAME...${RC}"

    case "$PACKAGER" in
        pacman)
            checkAURHelper
            # Remove old conflicting packages first
            if pacman -Q github-desktop-bin >/dev/null 2>&1; then
                printf "%b\n" "${YELLOW}[*] Removing old github-desktop-bin...${RC}"
                "$ESCALATION_TOOL" pacman -Rns --noconfirm github-desktop-bin 2>/dev/null || true
            fi
            if pacman -Q github-desktop >/dev/null 2>&1; then
                printf "%b\n" "${YELLOW}[*] Removing old github-desktop...${RC}"
                "$ESCALATION_TOOL" pacman -Rns --noconfirm github-desktop 2>/dev/null || true
            fi
            # Remove debug package if it conflicts
            if pacman -Q github-desktop-debug >/dev/null 2>&1; then
                printf "%b\n" "${YELLOW}[*] Removing old github-desktop-debug...${RC}"
                "$ESCALATION_TOOL" pacman -Rns --noconfirm github-desktop-debug 2>/dev/null || true
            fi
            printf "%b\n" "${YELLOW}[*] Installing github-desktop-plus-bin from AUR...${RC}"
            "$AUR_HELPER" -S --needed --noconfirm github-desktop-plus-bin
            ;;
        apt-get|nala)
            printf "%b\n" "${YELLOW}[*] Installing dependencies...${RC}"
            "$ESCALATION_TOOL" "$PACKAGER" update
            "$ESCALATION_TOOL" "$PACKAGER" install -y curl gnupg
            # Install via upstream .deb (Plus provides prebuilt binaries)
            printf "%b\n" "${YELLOW}[*] Downloading $APP_NAME .deb package...${RC}"
            TMP_DEB="/tmp/github-desktop-plus.deb"
            curl -fL "https://github.com/pol-rivero/github-desktop-plus/releases/download/v${APP_VERSION}/github-desktop-plus_${APP_VERSION}_amd64.deb" -o "$TMP_DEB" || {
                printf "%b\n" "${RED}[✗] Download failed. Falling back to AUR-style build...${RC}"
                rm -f "$TMP_DEB"
                return 1
            }
            "$ESCALATION_TOOL" apt-get install -y "$TMP_DEB"
            rm -f "$TMP_DEB"
            ;;
        dnf)
            printf "%b\n" "${YELLOW}[*] Downloading $APP_NAME .rpm package...${RC}"
            TMP_RPM="/tmp/github-desktop-plus.rpm"
            curl -fL "https://github.com/pol-rivero/github-desktop-plus/releases/download/v${APP_VERSION}/github-desktop-plus-${APP_VERSION}.x86_64.rpm" -o "$TMP_RPM" || {
                printf "%b\n" "${RED}[✗] Download failed.${RC}"
                rm -f "$TMP_RPM"
                return 1
            }
            "$ESCALATION_TOOL" "$PACKAGER" install -y "$TMP_RPM"
            rm -f "$TMP_RPM"
            ;;
        zypper)
            printf "%b\n" "${YELLOW}[*] Downloading $APP_NAME .rpm package...${RC}"
            TMP_RPM="/tmp/github-desktop-plus.rpm"
            curl -fL "https://github.com/pol-rivero/github-desktop-plus/releases/download/v${APP_VERSION}/github-desktop-plus-${APP_VERSION}.x86_64.rpm" -o "$TMP_RPM" || {
                printf "%b\n" "${RED}[✗] Download failed.${RC}"
                rm -f "$TMP_RPM"
                return 1
            }
            "$ESCALATION_TOOL" "$PACKAGER" install -y --allow-unsigned-rpm "$TMP_RPM"
            rm -f "$TMP_RPM"
            ;;
        *)
            printf "%b\n" "${RED}Unsupported package manager: $PACKAGER${RC}"
            printf "%b\n" "${YELLOW}Install manually from: https://github.com/pol-rivero/github-desktop-plus/releases${RC}"
            exit 1
            ;;
    esac
}

remove_old_version() {
    case "$PACKAGER" in
        pacman)
            "$ESCALATION_TOOL" pacman -Rns --noconfirm github-desktop-bin github-desktop github-desktop-debug 2>/dev/null || true
            ;;
        apt-get|nala)
            "$ESCALATION_TOOL" "$PACKAGER" remove -y github-desktop 2>/dev/null || true
            "$ESCALATION_TOOL" "$PACKAGER" autoremove -y 2>/dev/null || true
            ;;
        dnf|zypper)
            "$ESCALATION_TOOL" "$PACKAGER" remove -y github-desktop 2>/dev/null || true
            ;;
        *)
            ;;
    esac
}

verify_install() {
    printf "\n%b\n" "${CYAN}━━━ Verification ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RC}"

    # Check via pacman first (more reliable than command_exists in linutil env)
    if pacman -Q github-desktop-plus-bin >/dev/null 2>&1 || pacman -Q github-desktop-plus >/dev/null 2>&1; then
        VER=$(pacman -Q github-desktop-plus-bin 2>/dev/null | awk '{print $2}' || pacman -Q github-desktop-plus 2>/dev/null | awk '{print $2}')
        printf "%b\n" "${GREEN}[✓] $APP_NAME installed — v$VER${RC}"
        printf "%b\n" "${GREEN}=================================================================${RC}"
        printf "%b\n" "${GREEN}  Installation complete!${RC}"
        printf "%b\n" "${CYAN}  Launch: github-desktop${RC}"
        printf "%b\n" "${CYAN}  Copilot: Sign in → open a GitHub repo → click sparkles icon${RC}"
        printf "%b\n" "${GREEN}=================================================================${RC}"
    elif command_exists github-desktop; then
        printf "%b\n" "${GREEN}[✓] $APP_NAME installed (command found)${RC}"
        printf "%b\n" "${GREEN}=================================================================${RC}"
        printf "%b\n" "${GREEN}  Installation complete!${RC}"
        printf "%b\n" "${CYAN}  Launch: github-desktop${RC}"
        printf "%b\n" "${CYAN}  Copilot: Sign in → open a GitHub repo → click sparkles icon${RC}"
        printf "%b\n" "${GREEN}=================================================================${RC}"
    else
        printf "%b\n" "${RED}[✗] Installation may have failed. Check output above.${RC}"
        exit 1
    fi
}

checkEnv
checkEscalationTool
checkAURHelper
install_github_desktop_plus
verify_install
