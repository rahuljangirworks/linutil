#!/bin/sh -e

# Description: Install Desktop Plus (up-to-date fork with Copilot, Bitbucket & GitLab support)
# Project: desktop-plus/desktop-plus (v3.6+)
# Official Repos: https://desktop-plus.org
# Works on: Arch, Debian/Ubuntu, Fedora/RHEL, openSUSE

. ../../../common-script.sh

APP_NAME="Desktop Plus"

clear 2>/dev/null || true
printf "%b\n" "${CYAN}=================================================================${RC}"
printf "%b\n" "${YELLOW}               $APP_NAME Installer                             ${RC}"
printf "%b\n" "${CYAN}=================================================================${RC}"
printf "%b\n" "${GREEN}  - Up-to-date fork of GitHub Desktop for Linux (v3.6+)${RC}"
printf "%b\n" "${GREEN}  - Built-in GitHub Copilot commit message generation (✨)${RC}"
printf "%b\n" "${GREEN}  - Native GitHub, GitLab, Bitbucket & Codeberg integration${RC}"
printf "%b\n" "${GREEN}  - Installed via official repositories with automatic updates${RC}"
printf "%b\n" "${CYAN}=================================================================${RC}"
echo ""

detect_installed_version() {
    if command_exists desktop-plus; then
        desktop-plus --version 2>/dev/null | awk '{print $NF}' || echo "installed"
    elif command_exists github-desktop; then
        github-desktop --version 2>/dev/null | awk '{print $NF}' || echo "installed"
    elif pacman -Q desktop-plus-bin >/dev/null 2>&1 || pacman -Q desktop-plus >/dev/null 2>&1; then
        pacman -Q desktop-plus-bin 2>/dev/null | awk '{print $2}' || pacman -Q desktop-plus 2>/dev/null | awk '{print $2}'
    elif pacman -Q github-desktop-bin >/dev/null 2>&1 || pacman -Q github-desktop >/dev/null 2>&1; then
        pacman -Q github-desktop-bin 2>/dev/null | awk '{print $2}' || pacman -Q github-desktop 2>/dev/null | awk '{print $2}'
    elif command_exists rpm && rpm -q desktop-plus >/dev/null 2>&1; then
        rpm -q desktop-plus --qf '%{VERSION}' 2>/dev/null || echo "installed"
    elif command_exists dpkg-query && dpkg-query -W -f='${Version}' desktop-plus >/dev/null 2>&1; then
        dpkg-query -W -f='${Version}' desktop-plus 2>/dev/null || echo "installed"
    else
        echo ""
    fi
}

install_github_desktop_plus() {
    CURRENT_VER=$(detect_installed_version)

    if [ -n "$CURRENT_VER" ]; then
        printf "%b\n" "${GREEN}[✓] $APP_NAME or GitHub Desktop is already installed — v$CURRENT_VER${RC}"
        printf "%b\n" "${YELLOW}[*] Checking if upgrade is needed...${RC}"

        case "$CURRENT_VER" in
            3.4.*|3.3.*|3.2.*|3.1.*|3.0.*)
                printf "%b\n" "${YELLOW}[~] Your installed version ($CURRENT_VER) is too old for Copilot.${RC}"
                printf "%b\n" "${YELLOW}    Copilot requires v3.5+ (Desktop Plus v3.6+).${RC}"
                printf "%b\n" "${YELLOW}[*] Upgrading to $APP_NAME...${RC}"
                remove_old_version
                ;;
            *)
                printf "%b\n" "${GREEN}[✓] Installed version ($CURRENT_VER) supports Copilot.${RC}"
                create_convenience_symlink
                return 0
                ;;
        esac
    fi

    printf "%b\n" "${YELLOW}[*] Installing $APP_NAME via official repository...${RC}"

    case "$PACKAGER" in
        pacman)
            checkAURHelper
            remove_old_version
            printf "%b\n" "${YELLOW}[*] Installing desktop-plus-bin from AUR...${RC}"
            "$AUR_HELPER" -S --needed --noconfirm desktop-plus-bin
            ;;
        apt-get|nala)
            printf "%b\n" "${YELLOW}[*] Configuring official APT repository (apt.desktop-plus.org)...${RC}"
            "$ESCALATION_TOOL" "$PACKAGER" update
            "$ESCALATION_TOOL" "$PACKAGER" install -y curl gnupg
            curl -fsSL https://gpg.desktop-plus.org/public.key | "$ESCALATION_TOOL" gpg --dearmor --yes -o /usr/share/keyrings/desktop-plus.gpg
            echo "deb [arch=amd64,arm64 signed-by=/usr/share/keyrings/desktop-plus.gpg] https://apt.desktop-plus.org/ stable main" | "$ESCALATION_TOOL" tee /etc/apt/sources.list.d/desktop-plus.list >/dev/null
            "$ESCALATION_TOOL" "$PACKAGER" update
            "$ESCALATION_TOOL" "$PACKAGER" install -y desktop-plus
            ;;
        dnf|yum)
            printf "%b\n" "${YELLOW}[*] Configuring official RPM repository (rpm.desktop-plus.org)...${RC}"
            "$ESCALATION_TOOL" rpm --import https://gpg.desktop-plus.org/public.key
            printf "%s\n" "[desktop-plus]
name=Desktop Plus
baseurl=https://rpm.desktop-plus.org/
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://gpg.desktop-plus.org/public.key" | "$ESCALATION_TOOL" tee /etc/yum.repos.d/desktop-plus.repo >/dev/null
            "$ESCALATION_TOOL" "$PACKAGER" check-update --refresh || true
            "$ESCALATION_TOOL" "$PACKAGER" install -y desktop-plus
            ;;
        zypper)
            printf "%b\n" "${YELLOW}[*] Configuring official ZYpp repository (rpm.desktop-plus.org)...${RC}"
            "$ESCALATION_TOOL" rpm --import https://gpg.desktop-plus.org/public.key
            printf "%s\n" "[desktop-plus]
name=Desktop Plus
baseurl=https://rpm.desktop-plus.org/
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://gpg.desktop-plus.org/public.key" | "$ESCALATION_TOOL" tee /etc/zypp/repos.d/desktop-plus.repo >/dev/null
            "$ESCALATION_TOOL" zypper refresh
            "$ESCALATION_TOOL" zypper install -y desktop-plus
            ;;
        *)
            printf "%b\n" "${RED}Unsupported package manager: $PACKAGER${RC}"
            printf "%b\n" "${YELLOW}See https://desktop-plus.org for manual install options.${RC}"
            exit 1
            ;;
    esac

    create_convenience_symlink
}

remove_old_version() {
    case "$PACKAGER" in
        pacman)
            for pkg in github-desktop-bin github-desktop github-desktop-debug github-desktop-plus-bin; do
                if pacman -Q "$pkg" >/dev/null 2>&1; then
                    printf "%b\n" "${YELLOW}[*] Removing old $pkg...${RC}"
                    "$ESCALATION_TOOL" pacman -Rns --noconfirm "$pkg" 2>/dev/null || true
                fi
            done
            ;;
        apt-get|nala)
            "$ESCALATION_TOOL" "$PACKAGER" remove -y github-desktop 2>/dev/null || true
            "$ESCALATION_TOOL" "$PACKAGER" autoremove -y 2>/dev/null || true
            ;;
        dnf|yum|zypper)
            "$ESCALATION_TOOL" "$PACKAGER" remove -y github-desktop 2>/dev/null || true
            ;;
        *)
            ;;
    esac
}

create_convenience_symlink() {
    if command_exists desktop-plus && ! command_exists github-desktop; then
        DESKTOP_BIN="$(command -v desktop-plus)"
        if [ -x "$DESKTOP_BIN" ]; then
            printf "%b\n" "${CYAN}[*] Adding convenience symlink: github-desktop -> ${DESKTOP_BIN}${RC}"
            "$ESCALATION_TOOL" ln -sf "$DESKTOP_BIN" /usr/local/bin/github-desktop 2>/dev/null || true
        fi
    fi
}

verify_install() {
    printf "\n%b\n" "${CYAN}━━━ Verification ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RC}"

    INSTALLED_VER=$(detect_installed_version)

    if command_exists desktop-plus || command_exists github-desktop || [ -n "$INSTALLED_VER" ]; then
        printf "%b\n" "${GREEN}[✓] $APP_NAME installed successfully — v${INSTALLED_VER:-ready}${RC}"
        printf "%b\n" "${GREEN}=================================================================${RC}"
        printf "%b\n" "${GREEN}  Installation complete!${RC}"
        printf "%b\n" "${CYAN}  Launch commands: desktop-plus OR github-desktop${RC}"
        printf "%b\n" "${CYAN}  Copilot Setup:   1. File > Options > Accounts (Sign in to GitHub)${RC}"
        printf "%b\n" "${CYAN}                   2. Open any repository hosted on GitHub${RC}"
        printf "%b\n" "${CYAN}                   3. Click the ✨ sparkle icon in the commit summary box${RC}"
        printf "%b\n" "${GREEN}=================================================================${RC}"
    else
        printf "%b\n" "${RED}[✗] Installation verification failed. Check output above.${RC}"
        exit 1
    fi
}

checkEnv
install_github_desktop_plus
verify_install
