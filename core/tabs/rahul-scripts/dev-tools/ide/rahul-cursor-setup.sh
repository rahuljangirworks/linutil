#!/bin/sh -e

# Description: Install Cursor Desktop (AI code editor) via official DNF repository
# Source: https://downloads.cursor.com/yumrepo
# Works on: Fedora, RHEL, CentOS, openSUSE

. ../../../common-script.sh

checkEnv

APP_NAME="Cursor"
REPO_FILE="/etc/yum.repos.d/cursor.repo"
REPO_URL="https://downloads.cursor.com/yumrepo"
GPG_KEY="https://downloads.cursor.com/keys/anysphere.asc"

clear 2>/dev/null || true
printf "%b\n" "${CYAN}=================================================================${RC}"
printf "%b\n" "${YELLOW}        $APP_NAME Installer (Official RPM Repository)           ${RC}"
printf "%b\n" "${CYAN}=================================================================${RC}"
printf "%b\n" "${GREEN}  - Official Cursor RPM from downloads.cursor.com${RC}"
printf "%b\n" "${GREEN}  - AI-native IDE (VS Code-based) with agents${RC}"
printf "%b\n" "${GREEN}  - Auto-updates via dnf${RC}"
printf "%b\n" "${CYAN}=================================================================${RC}"
echo ""

# ─── Check if already installed ──────────────────────────────────────────────
check_existing() {
    if command -v cursor >/dev/null 2>&1; then
        CUR_VER=$(cursor --version 2>/dev/null | head -n 1 || true)
        printf "%b\n" "${GREEN}[✓] Cursor already installed: $CUR_VER${RC}"
        printf "%b" "${YELLOW}[*] Check for updates? [Y/n]: ${RC}"
        read -r update_choice
        case "${update_choice:-Y}" in
            n|N|no|NO)
                printf "%b\n" "${CYAN}Skipping update check.${RC}"
                return 1
                ;;
        esac
    fi
    return 0
}

# ─── Add Cursor DNF Repository ───────────────────────────────────────────────
add_cursor_repo() {
    printf "%b\n" "${CYAN}━━━ Adding Cursor DNF Repository ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RC}"

    if [ -f "$REPO_FILE" ]; then
        printf "%b\n" "${YELLOW}[*] Cursor repository exists. Updating configuration...${RC}"
    fi

    printf "%b\n" "${YELLOW}[*] Creating Cursor repository...${RC}"

    if [ -n "$ESCALATION_TOOL" ]; then
        "$ESCALATION_TOOL" tee "$REPO_FILE" > /dev/null <<EOF
[cursor]
name=Cursor
baseurl=$REPO_URL
enabled=1
gpgcheck=1
repo_gpgcheck=0
gpgkey=$GPG_KEY
EOF
    else
        tee "$REPO_FILE" > /dev/null <<EOF
[cursor]
name=Cursor
baseurl=$REPO_URL
enabled=1
gpgcheck=1
repo_gpgcheck=0
gpgkey=$GPG_KEY
EOF
    fi

    if [ -f "$REPO_FILE" ]; then
        printf "%b\n" "${GREEN}[✓] Cursor repository added: $REPO_FILE${RC}"
    else
        printf "%b\n" "${RED}[✗] Failed to create repository file${RC}"
        return 1
    fi

    echo ""
}

# ─── Install/Update Cursor ───────────────────────────────────────────────────
install_cursor() {
    printf "%b\n" "${CYAN}━━━ Installing $APP_NAME ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RC}"

    case "$PACKAGER" in
        dnf)
            printf "%b\n" "${YELLOW}[*] Refreshing package cache...${RC}"
            "$ESCALATION_TOOL" dnf check-update --refresh 2>/dev/null || true

            if rpm -q cursor >/dev/null 2>&1; then
                printf "%b\n" "${YELLOW}[*] Updating Cursor to latest version...${RC}"
                "$ESCALATION_TOOL" dnf update -y cursor
            else
                printf "%b\n" "${YELLOW}[*] Installing Cursor...${RC}"
                "$ESCALATION_TOOL" dnf install -y cursor
            fi
            ;;
        zypper)
            printf "%b\n" "${YELLOW}[*] Refreshing package cache...${RC}"
            "$ESCALATION_TOOL" zypper refresh 2>/dev/null || true

            if rpm -q cursor >/dev/null 2>&1; then
                printf "%b\n" "${YELLOW}[*] Updating Cursor to latest version...${RC}"
                "$ESCALATION_TOOL" zypper update -y cursor
            else
                printf "%b\n" "${YELLOW}[*] Installing Cursor...${RC}"
                "$ESCALATION_TOOL" zypper install -y cursor
            fi
            ;;
        pacman)
            printf "%b\n" "${YELLOW}[*] Installing from AUR (cursor-bin)...${RC}"
            if command -v yay >/dev/null 2>&1; then
                yay -S --noconfirm cursor-bin
            elif command -v paru >/dev/null 2>&1; then
                paru -S --noconfirm cursor-bin
            else
                printf "%b\n" "${RED}[✗] No AUR helper found. Install yay or paru first.${RC}"
                printf "%b\n" "${YELLOW}    Or download manually: https://cursor.com/download${RC}"
                return 1
            fi
            ;;
        apt-get|nala)
            printf "%b\n" "${YELLOW}[*] Installing Cursor .deb...${RC}"
            CURSOR_DEB=$(mktemp /tmp/cursor-XXXXXX.deb)
            curl -fL "https://api2.cursor.sh/updates/download/golden/linux-x64-deb/cursor/3.5" -o "$CURSOR_DEB" || {
                printf "%b\n" "${RED}[✗] Download failed${RC}"
                rm -f "$CURSOR_DEB"
                return 1
            }
            "$ESCALATION_TOOL" dpkg -i "$CURSOR_DEB" || "$ESCALATION_TOOL" apt-get install -f -y
            rm -f "$CURSOR_DEB"
            ;;
        *)
            printf "%b\n" "${RED}[✗] Unsupported package manager: $PACKAGER${RC}"
            printf "%b\n" "${YELLOW}    Download manually: https://cursor.com/download${RC}"
            return 1
            ;;
    esac

    if [ $? -eq 0 ]; then
        printf "%b\n" "${GREEN}[✓] Cursor installed/updated successfully${RC}"
    else
        printf "%b\n" "${RED}[✗] Installation failed${RC}"
        return 1
    fi

    echo ""
}

# ─── Post-install setup ──────────────────────────────────────────────────────
post_install() {
    printf "%b\n" "${CYAN}━━━ Post-Install Setup ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RC}"

    # Ensure cursor is in PATH
    CURSOR_BIN=$(command -v cursor 2>/dev/null || echo "/usr/bin/cursor")
    if [ -x "$CURSOR_BIN" ]; then
        printf "%b\n" "${GREEN}[✓] Cursor binary: $CURSOR_BIN${RC}"
    fi

    # Update desktop database
    if command -v update-desktop-database >/dev/null 2>&1; then
        update-desktop-database 2>/dev/null || true
    fi

    # Update icon cache
    if command -v gtk-update-icon-cache >/dev/null 2>&1; then
        gtk-update-icon-cache -f /usr/share/icons/hicolor 2>/dev/null || true
    fi

    printf "%b\n" "${GREEN}[✓] Desktop integration complete${RC}"
    echo ""
}

# ─── Verify ──────────────────────────────────────────────────────────────────
verify_install() {
    printf "%b\n" "${CYAN}━━━ Verification ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RC}"

    PASS=true

    if command -v cursor >/dev/null 2>&1; then
        VER=$(cursor --version 2>/dev/null | head -n 1 || true)
        printf "%b\n" "${GREEN}[✓] cursor command: $(command -v cursor)${RC}"
        [ -n "$VER" ] && printf "%b\n" "${GREEN}    Version: $VER${RC}"
    else
        printf "%b\n" "${RED}[✗] cursor command not found${RC}"
        PASS=false
    fi

    if [ -f /usr/share/applications/cursor.desktop ] || [ -f ~/.local/share/applications/cursor.desktop ]; then
        printf "%b\n" "${GREEN}[✓] Desktop entry found${RC}"
    else
        printf "%b\n" "${YELLOW}[~] Desktop entry not found${RC}"
    fi

    if [ -f "$REPO_FILE" ]; then
        printf "%b\n" "${GREEN}[✓] DNF repository: $REPO_FILE${RC}"
    fi

    echo ""
    if [ "$PASS" = true ]; then
        printf "%b\n" "${GREEN}=================================================================${RC}"
        printf "%b\n" "${GREEN}  $APP_NAME installation complete!${RC}"
        printf "%b\n" "${CYAN}  Launch: cursor${RC}"
        printf "%b\n" "${CYAN}  Or find 'Cursor' in app menu${RC}"
        printf "%b\n" "${CYAN}  Update: sudo dnf update cursor${RC}"
        printf "%b\n" "${GREEN}=================================================================${RC}"
    else
        printf "%b\n" "${RED}=================================================================${RC}"
        printf "%b\n" "${RED}  Installation completed with warnings. Check output above.${RC}"
        printf "%b\n" "${RED}=================================================================${RC}"
    fi
}

# ─── Main ────────────────────────────────────────────────────────────────────
if check_existing; then
    add_cursor_repo
    install_cursor
    post_install
fi
verify_install
