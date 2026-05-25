#!/bin/sh -e

# Description: Install Cursor Desktop (AI code editor) from official golden channel .deb
# Source: https://api2.cursor.sh/updates/download/golden/linux-x64-deb/cursor/3.5
# Works on: Arch, Debian, Fedora, openSUSE

. ../common-script.sh

APP_NAME="Cursor Desktop"
CURSOR_CHANNEL="${CURSOR_CHANNEL:-3.5}"
DEB_URL="https://api2.cursor.sh/updates/download/golden/linux-x64-deb/cursor/${CURSOR_CHANNEL}"
INSTALL_MARKER="/usr/share/cursor/cursor"
CURSOR_BIN="/usr/share/cursor/bin/cursor"
CURSOR_SYMLINK="/usr/bin/cursor"

clear 2>/dev/null || true
printf "%b\n" "${CYAN}=================================================================${RC}"
printf "%b\n" "${YELLOW}        $APP_NAME Installer (channel ${CURSOR_CHANNEL})              ${RC}"
printf "%b\n" "${CYAN}=================================================================${RC}"
printf "%b\n" "${GREEN}  - Official Cursor .deb from api2.cursor.sh${RC}"
printf "%b\n" "${GREEN}  - AI-native IDE (VS Code-based) with agents${RC}"
printf "%b\n" "${GREEN}  - Desktop entry + /usr/bin/cursor launcher${RC}"
printf "%b\n" "${CYAN}=================================================================${RC}"
echo ""

get_installed_version() {
    if [ -f /usr/share/cursor/resources/app/package.json ]; then
        sed -n 's/.*"version": "\([^"]*\)".*/\1/p' /usr/share/cursor/resources/app/package.json | head -n 1
        return
    fi
    if pacman -Q cursor-bin >/dev/null 2>&1; then
        pacman -Q cursor-bin | awk '{print $2}'
        return
    fi
    if pacman -Q cursor >/dev/null 2>&1; then
        pacman -Q cursor | awk '{print $2}'
        return
    fi
    if command_exists cursor; then
        cursor --version 2>/dev/null | head -n 1 || true
    fi
}

get_deb_version() {
    deb_file="$1"
    tmp_dir=$(mktemp -d)
    ver=""
    if cd "$tmp_dir" 2>/dev/null; then
        if bsdtar -xf "$deb_file" control.tar.xz 2>/dev/null && bsdtar -xf control.tar.xz control 2>/dev/null; then
            ver=$(sed -n 's/^Version: //p' control | head -n 1 | cut -d- -f1)
        fi
        cd - >/dev/null 2>&1 || true
    fi
    rm -rf "$tmp_dir"
    printf '%s' "$ver"
}

install_pkg_if_missing() {
    pkg="$1"
    case "$PACKAGER" in
        pacman)
            if ! pacman -Q "$pkg" >/dev/null 2>&1; then
                printf "%b\n" "${YELLOW}[*] Installing $pkg...${RC}"
                "$ESCALATION_TOOL" "$PACKAGER" -S --needed --noconfirm "$pkg"
            else
                printf "%b\n" "${GREEN}[✓] $pkg already installed${RC}"
            fi
            ;;
        apt-get|nala)
            if ! dpkg -l "$pkg" 2>/dev/null | /usr/bin/grep -q '^ii'; then
                printf "%b\n" "${YELLOW}[*] Installing $pkg...${RC}"
                "$ESCALATION_TOOL" "$PACKAGER" update
                "$ESCALATION_TOOL" "$PACKAGER" install -y "$pkg"
            else
                printf "%b\n" "${GREEN}[✓] $pkg already installed${RC}"
            fi
            ;;
        dnf|zypper)
            if ! rpm -q "$pkg" >/dev/null 2>&1; then
                printf "%b\n" "${YELLOW}[*] Installing $pkg...${RC}"
                "$ESCALATION_TOOL" "$PACKAGER" install -y "$pkg"
            else
                printf "%b\n" "${GREEN}[✓] $pkg already installed${RC}"
            fi
            ;;
        *)
            printf "%b\n" "${YELLOW}[~] Skipping $pkg (install manually if Cursor fails to start)${RC}"
            ;;
    esac
}

install_dependencies() {
    printf "%b\n" "${CYAN}[*] Installing runtime dependencies...${RC}"

    install_pkg_if_missing curl

    case "$PACKAGER" in
        pacman)
            if ! command_exists bsdtar; then
                install_pkg_if_missing libarchive
            else
                printf "%b\n" "${GREEN}[✓] bsdtar already available${RC}"
            fi
            for pkg in alsa-lib at-spi2-core atk cairo libcups curl dbus expat mesa glib2 gtk3 nss pango systemd-libs libx11 libxcb libxcomposite libxdamage libxext libxfixes libxkbcommon libxkbfile libxrandr xdg-utils desktop-file-utils; do
                install_pkg_if_missing "$pkg"
            done
            # Vulkan is recommended by Cursor but optional
            if ! pacman -Qs '^vulkan' >/dev/null 2>&1; then
                printf "%b\n" "${YELLOW}[~] No Vulkan driver found (optional). Install vulkan-radeon, vulkan-intel, or nvidia-utils if GPU issues occur.${RC}"
            else
                printf "%b\n" "${GREEN}[✓] Vulkan driver already installed${RC}"
            fi
            ;;
        apt-get|nala)
            if ! command_exists bsdtar; then
                install_pkg_if_missing libarchive-tools
            fi
            "$ESCALATION_TOOL" "$PACKAGER" update
            "$ESCALATION_TOOL" "$PACKAGER" install -y curl ca-certificates libasound2 libatk-bridge2.0-0 libatk1.0-0 libatspi2.0-0 libcairo2 libcups2 libcurl4 libdbus-1-3 libexpat1 libgbm1 libglib2.0-0 libgtk-3-0 libnspr4 libnss3 libpango-1.0-0 libx11-6 libxcb1 libxcomposite1 libxdamage1 libxext6 libxfixes3 libxkbcommon0 libxkbfile1 libxrandr2 xdg-utils libvulkan1
            ;;
        dnf)
            "$ESCALATION_TOOL" "$PACKAGER" install -y curl alsa-lib atk at-spi2-atk cairo cups-libs dbus-libs expat mesa-libgbm glib2 gtk3 nss pango libX11 libxcb libXcomposite libXdamage libXext libXfixes libxkbcommon libxkbfile libXrandr xdg-utils vulkan
            ;;
        zypper)
            "$ESCALATION_TOOL" "$PACKAGER" install -y curl alsa atk at-spi2 cairo libcups2 libcurl4 libdbus-1-3 libexpat1 Mesa-libgbm1 glib2 gtk3 mozilla-nss pango libX11-6 libxcb1 libXcomposite1 libXdamage1 libXext6 libXfixes3 libxkbcommon0 libxkbfile1 libXrandr2 xdg-utils libvulkan1
            ;;
        *)
            printf "%b\n" "${YELLOW}[~] Dependency auto-install skipped for $PACKAGER${RC}"
            ;;
    esac
}

stop_running_cursor() {
    CURSOR_PIDS=$(pgrep -f "/usr/share/cursor/cursor" 2>/dev/null || pgrep -x cursor 2>/dev/null || true)
    if [ -n "$CURSOR_PIDS" ]; then
        printf "%b\n" "${YELLOW}[*] Closing running Cursor processes before install...${RC}"
        echo "$CURSOR_PIDS" | xargs kill 2>/dev/null || true
        sleep 2
    fi
}

remove_aur_cursor_if_present() {
    case "$PACKAGER" in
        pacman)
            if pacman -Q cursor-bin >/dev/null 2>&1 || pacman -Q cursor >/dev/null 2>&1; then
                printf "%b\n" "${YELLOW}[*] Removing AUR cursor package to avoid conflicts with official .deb...${RC}"
                "$ESCALATION_TOOL" pacman -Rns --noconfirm cursor-bin cursor 2>/dev/null || true
            fi
            ;;
        *)
            ;;
    esac
}

post_install_symlinks() {
    if [ ! -x "$CURSOR_BIN" ]; then
        printf "%b\n" "${RED}[✗] Cursor binary not found at $CURSOR_BIN${RC}"
        return 1
    fi

    printf "%b\n" "${YELLOW}[*] Linking $CURSOR_SYMLINK -> $CURSOR_BIN${RC}"
    "$ESCALATION_TOOL" rm -f "$CURSOR_SYMLINK"
    "$ESCALATION_TOOL" ln -sf "$CURSOR_BIN" "$CURSOR_SYMLINK"

    if command_exists update-desktop-database; then
        "$ESCALATION_TOOL" update-desktop-database 2>/dev/null || true
    fi

    if command_exists update-mime-database; then
        "$ESCALATION_TOOL" update-mime-database /usr/share/mime 2>/dev/null || true
    fi

    if command_exists apparmor_parser && [ -f /etc/apparmor.d/cursor-sandbox ]; then
        if systemctl is-active --quiet apparmor 2>/dev/null; then
            "$ESCALATION_TOOL" apparmor_parser -r /etc/apparmor.d/cursor-sandbox 2>/dev/null || true
        fi
    fi
}

install_via_deb() {
    TMP_DIR=$(mktemp -d)
    TMP_DEB="$TMP_DIR/cursor.deb"

    printf "%b\n" "${YELLOW}[*] Downloading $APP_NAME (channel ${CURSOR_CHANNEL})...${RC}"
    printf "%b\n" "${CYAN}    URL: $DEB_URL${RC}"
    curl -fL "$DEB_URL" -o "$TMP_DEB" || {
        printf "%b\n" "${RED}[✗] Download failed.${RC}"
        rm -rf "$TMP_DIR"
        return 1
    }

    NEW_VER=$(get_deb_version "$TMP_DEB")
    if [ -n "$NEW_VER" ]; then
        printf "%b\n" "${GREEN}[✓] Package version: $NEW_VER${RC}"
    fi

    INSTALLED_VER=$(get_installed_version)
    if [ -n "$INSTALLED_VER" ] && [ -f "$INSTALL_MARKER" ]; then
        if [ "$INSTALLED_VER" = "$NEW_VER" ]; then
            printf "%b\n" "${GREEN}[✓] Cursor $INSTALLED_VER already installed — nothing to do.${RC}"
            rm -rf "$TMP_DIR"
            return 0
        fi
        printf "%b\n" "${YELLOW}[*] Upgrading Cursor $INSTALLED_VER -> $NEW_VER${RC}"
        stop_running_cursor
    fi

    remove_aur_cursor_if_present
    stop_running_cursor

    printf "%b\n" "${YELLOW}[*] Installing Cursor from .deb...${RC}"

    if command_exists dpkg && [ "$PACKAGER" != "pacman" ]; then
        "$ESCALATION_TOOL" dpkg -i "$TMP_DEB" || {
            case "$PACKAGER" in
                apt-get|nala)
                    printf "%b\n" "${YELLOW}[~] Fixing dependencies...${RC}"
                    "$ESCALATION_TOOL" "$PACKAGER" install -f -y
                    ;;
            esac
        }
    elif command_exists bsdtar; then
        cd "$TMP_DIR"
        bsdtar -xf "$TMP_DEB" data.tar.* 2>/dev/null || bsdtar -xf "$TMP_DEB"
        for datafile in data.tar.*; do
            if [ -f "$datafile" ]; then
                printf "%b\n" "${YELLOW}[*] Extracting $datafile to / ...${RC}"
                "$ESCALATION_TOOL" bsdtar -xf "$datafile" -C /
                break
            fi
        done
        cd - >/dev/null
        post_install_symlinks
    else
        cd "$TMP_DIR"
        ar x "$TMP_DEB" 2>/dev/null
        for datafile in data.tar.*; do
            if [ -f "$datafile" ]; then
                "$ESCALATION_TOOL" tar -xf "$datafile" -C /
                break
            fi
        done
        cd - >/dev/null
        post_install_symlinks
    fi

    rm -rf "$TMP_DIR"
    printf "%b\n" "${GREEN}[✓] Cursor Desktop installed${RC}"
}

install_cursor() {
    printf "\n%b\n" "${CYAN}━━━ Installing $APP_NAME ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RC}"

    case "$PACKAGER" in
        pacman|apt-get|nala|dnf|zypper)
            install_via_deb
            ;;
        *)
            printf "%b\n" "${RED}Unsupported package manager: $PACKAGER${RC}"
            printf "%b\n" "${YELLOW}Download manually: $DEB_URL${RC}"
            exit 1
            ;;
    esac
}

configure_earlyoom() {
    EARLYOOM_CONF="/etc/default/earlyoom"
    if [ ! -f "$EARLYOOM_CONF" ] || ! systemctl is-active --quiet earlyoom 2>/dev/null; then
        return 0
    fi
    if /usr/bin/grep -q 'cursor' "$EARLYOOM_CONF" 2>/dev/null; then
        printf "%b\n" "${GREEN}[✓] earlyoom already configured to avoid Cursor${RC}"
        return 0
    fi
    printf "%b\n" "${YELLOW}[*] Updating earlyoom to stop killing Cursor on low memory...${RC}"
    "$ESCALATION_TOOL" sed -i "s|sshd)\\\$|sshd|cursor)\\\$|" "$EARLYOOM_CONF" 2>/dev/null || \
    "$ESCALATION_TOOL" sed -i "s|sshd)'|sshd|cursor)'|" "$EARLYOOM_CONF" 2>/dev/null || true
    if /usr/bin/grep -q 'cursor' "$EARLYOOM_CONF" 2>/dev/null; then
        "$ESCALATION_TOOL" systemctl restart earlyoom 2>/dev/null || true
        printf "%b\n" "${GREEN}[✓] earlyoom restarted — Cursor exempt from SIGTERM kills${RC}"
    else
        printf "%b\n" "${YELLOW}[~] Could not patch $EARLYOOM_CONF automatically.${RC}"
        printf "%b\n" "${YELLOW}    Add cursor to --avoid in $EARLYOOM_CONF, then: sudo systemctl restart earlyoom${RC}"
    fi
}

setup_user_launcher() {
    BIN_DIR="${XDG_BIN_DIR:-$HOME/.local/bin}"
    LAUNCHER="$BIN_DIR/cursor-launch"
    DESKTOP_DIR="$HOME/.local/share/applications"
    DESKTOP_FILE="$DESKTOP_DIR/cursor.desktop"

    mkdir -p "$BIN_DIR" "$DESKTOP_DIR"
    cat > "$LAUNCHER" <<'EOF'
#!/bin/sh
# RahulOS: launch Cursor without getting killed by earlyoom during login.
# Close heavy apps first if swap is full (free -h).
exec /usr/share/cursor/bin/cursor --disable-gpu "$@"
EOF
    chmod +x "$LAUNCHER"

    if [ -f /usr/share/applications/cursor.desktop ]; then
        sed 's|Exec=/usr/share/cursor/cursor %F|Exec=env CURSOR_DISABLE_GPU=1 cursor-launch %F|; s|Exec=/usr/share/cursor/cursor --new-window %F|Exec=cursor-launch --new-window %F|' \
            /usr/share/applications/cursor.desktop > "$DESKTOP_FILE"
    fi

    if command_exists update-desktop-database; then
        update-desktop-database "$DESKTOP_DIR" 2>/dev/null || true
    fi

    printf "%b\n" "${GREEN}[✓] User launcher: $LAUNCHER${RC}"
    printf "%b\n" "${CYAN}    Use: cursor-launch   (lighter GPU, survives earlyoom patch)${RC}"
}

verify_install() {
    printf "\n%b\n" "${CYAN}━━━ Verification ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RC}"

    if [ -x "$INSTALL_MARKER" ] || [ -x "$CURSOR_BIN" ]; then
        VER=$(get_installed_version)
        printf "%b\n" "${GREEN}[✓] $APP_NAME installed${RC}"
        [ -n "$VER" ] && printf "%b\n" "${GREEN}    Version: $VER${RC}"
    elif command_exists cursor; then
        VER=$(cursor --version 2>/dev/null | head -n 1 || true)
        printf "%b\n" "${GREEN}[✓] cursor command available${RC}"
        [ -n "$VER" ] && printf "%b\n" "${GREEN}    $VER${RC}"
    elif [ -f /usr/share/applications/cursor.desktop ]; then
        printf "%b\n" "${GREEN}[✓] Desktop entry found${RC}"
    else
        printf "%b\n" "${RED}[✗] Installation may have failed. Check output above.${RC}"
        exit 1
    fi

    configure_earlyoom
    setup_user_launcher

    printf "%b\n" "${GREEN}=================================================================${RC}"
    printf "%b\n" "${GREEN}  $APP_NAME installation complete!${RC}"
    printf "%b\n" "${CYAN}  Launch: cursor-launch   (recommended on RahulOS)${RC}"
    printf "%b\n" "${CYAN}  Or: cursor / rofi → Cursor${RC}"
    printf "%b\n" "${YELLOW}  If login crashes: free RAM (swap full), then cursor-launch${RC}"
    printf "%b\n" "${CYAN}  Re-run to upgrade from channel ${CURSOR_CHANNEL}${RC}"
    printf "%b\n" "${GREEN}=================================================================${RC}"
}

checkEnv
checkEscalationTool
checkArch
install_dependencies
install_cursor
verify_install
