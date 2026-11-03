#!/bin/sh -e

# Description: Clean setup and reinstall for Google Antigravity suite (IDE, Desktop Agent, CLI).
# Rerunnable:  Yes - safely updates applications without wiping user logins unless --hard-reset is requested.
# Author:      Rahul Jangir

case "$0" in
    */*) script_path="$0" ;;
    *) script_path="$(command -v -- "$0" 2>/dev/null || printf "%s\n" "$0")" ;;
esac
SCRIPT_DIR="$(dirname "$script_path")"
SCRIPT_DIR="$(cd "$SCRIPT_DIR" && pwd)"
unset script_path

if [ -f "$SCRIPT_DIR/../../common-script.sh" ]; then
    . "$SCRIPT_DIR/../../common-script.sh"
elif [ -f "../../common-script.sh" ]; then
    . ../../common-script.sh
else
    RC='\033[0m'
    RED='\033[31m'
    YELLOW='\033[33m'
    CYAN='\033[36m'
    GREEN='\033[32m'
fi

# ── Explicit Permanent Deletion Binary ────────────────────────────────────────
if [ -x "/usr/bin/rm" ]; then
    RM_CMD="/usr/bin/rm"
elif [ -x "/bin/rm" ]; then
    RM_CMD="/bin/rm"
else
    RM_CMD="rm"
fi

# ── Isolated Paths & Versions ─────────────────────────────────────────────────
APP_DIR="$HOME/.local/antigravity-app"
IDE_DIR="$HOME/.local/antigravity-ide"
BIN_DIR="$HOME/.local/bin"
DESKTOP_DIR="$HOME/.local/share/applications"
STATE_DIR="$HOME/.local/state"
ICON_DIR="$HOME/.local/share/icons/hicolor/256x256/apps"

ICON_FILE_APP="$ICON_DIR/antigravity.png"
ICON_FILE_IDE="$ICON_DIR/antigravity-ide.png"
ICON_URL="https://res.cloudinary.com/utehls4u/image/upload/v1793682047/Google-Antigravity-Icon-Full-Color_eosfko.png"
ASSET_ICON="$SCRIPT_DIR/../assets/google-antigravity.png"

VERSION_APP="2.28.2"
BUILD_APP="5937220255875072"

VERSION_IDE="2.6.0"
BUILD_IDE="5526304964083712"

HARD_RESET=false

detect_arch() {
    ARCH=$(uname -m)
    case "$ARCH" in
        x86_64|amd64)
            PLATFORM="linux-x64"
            ;;
        aarch64|arm64)
            PLATFORM="linux-arm"
            ;;
        *)
            printf "%b\n" "${RED}[✗] Unsupported architecture: $ARCH${RC}"
            exit 1
            ;;
    esac
}

# Targeted process management so one tool doesn't disrupt the other
stop_app_processes() {
    printf "%b\n" "${YELLOW}[*] Terminating running Antigravity App processes...${RC}"
    pkill -x Antigravity 2>/dev/null || true
    pkill -x antigravity 2>/dev/null || true
    sleep 1
}

stop_ide_processes() {
    printf "%b\n" "${YELLOW}[*] Terminating running Antigravity IDE processes...${RC}"
    pkill -x antigravity-ide 2>/dev/null || true
    sleep 1
}

stop_cli_processes() {
    printf "%b\n" "${YELLOW}[*] Terminating running Antigravity CLI processes...${RC}"
    pkill -f 'agy ' 2>/dev/null || true
    sleep 1
}

stop_all_processes() {
    stop_app_processes
    stop_ide_processes
    stop_cli_processes
}

# Verify an existing archive before reusing it so the App installer cannot
# accidentally consume the IDE tarball (or vice versa).
archive_has_executable() {
    archive="$1"
    executable_name="$2"

    tar -tzf "$archive" 2>/dev/null | grep -i -E "(^|/)${executable_name}$" >/dev/null 2>&1
}

reuse_existing_archive() {
    candidate="$1"
    target="$2"
    executable_name="$3"

    [ -f "$candidate" ] && [ -s "$candidate" ] || return 1

    if archive_has_executable "$candidate" "$executable_name"; then
        printf "%b\n" "${GREEN}[✓] Found existing archive: $candidate${RC}"
        cp "$candidate" "$target"
        return 0
    fi

    printf "%b\n" "${YELLOW}[~] Ignoring mismatched archive: $candidate (missing '$executable_name')${RC}"
    return 1
}

# ── Smart Archive Acquisition (Re-uses ~/Downloads if available) ─────────────
acquire_archive() {
    url="$1"
    target="$2"
    expected_name="$3"
    executable_name="$4"

    # Check ~/Downloads first, but only accept archives for this product.
    if [ "$expected_name" = "Antigravity.tar.gz" ]; then
        for candidate in "$HOME/Downloads/Antigravity.tar.gz" \
                         "$HOME/Downloads/antigravity.tar.gz" \
                         "$HOME/Downloads/Antigravity-linux-x64.tar.gz" \
                         "$HOME/Downloads/Antigravity-x64.tar.gz"; do
            reuse_existing_archive "$candidate" "$target" "$executable_name" && return 0
        done
    else
        for candidate in "$HOME/Downloads/Antigravity IDE.tar.gz" \
                         "$HOME/Downloads/Antigravity-IDE.tar.gz" \
                         "$HOME/Downloads/antigravity-ide.tar.gz"; do
            reuse_existing_archive "$candidate" "$target" "$executable_name" && return 0
        done
    fi

    printf "%b\n" "${YELLOW}[*] Downloading from Google CDN: $url...${RC}"
    curl -fL --retry 3 "$url" -o "$target" || {
        printf "%b\n" "${RED}[✗] Download failed from: $url${RC}"
        return 1
    }
}

# ── Strict, Isolated Clean Functions ──────────────────────────────────────────
clean_agent_app() {
    printf "%b\n" "${YELLOW}[*] Cleaning previous Antigravity Desktop App installation...${RC}"

    # Remove installation directories and binary
    "$RM_CMD" -rf "$APP_DIR" "/opt/antigravity"
    "$RM_CMD" -f "$BIN_DIR/antigravity"
    "$RM_CMD" -f "$DESKTOP_DIR/antigravity.desktop"
    "$RM_CMD" -f "$ICON_FILE_APP"

    # Only wipe user session and cache if explicitly requested via --hard-reset
    if [ "$HARD_RESET" = true ]; then
        printf "%b\n" "${RED}[!] Hard reset: Removing Antigravity App user data and login sessions...${RC}"
        "$RM_CMD" -rf "$HOME/.config/Antigravity" "$HOME/.config/antigravity"
        "$RM_CMD" -rf "$HOME/.cache/Antigravity" "$HOME/.cache/antigravity"
        "$RM_CMD" -rf "$HOME/.gemini/antigravity"
    else
        printf "%b\n" "${GREEN}[✓] User data and login sessions preserved in ~/.config/Antigravity${RC}"
    fi

    # Remove residual staging and backup folders
    for pattern in "$HOME"/Antigravity-backup-* "$HOME"/antigravity-app.*; do
        [ -e "$pattern" ] && "$RM_CMD" -rf "$pattern"
    done

    printf "%b\n" "${GREEN}[✓] Antigravity App cleanup complete${RC}"
}

clean_ide() {
    printf "%b\n" "${YELLOW}[*] Cleaning previous Antigravity IDE installation...${RC}"

    # Remove installation directories and binary
    "$RM_CMD" -rf "$IDE_DIR" "/opt/antigravity-ide"
    # Also clean legacy location if it existed
    [ -d "$HOME/.local/antigravity" ] && "$RM_CMD" -rf "$HOME/.local/antigravity"
    "$RM_CMD" -f "$BIN_DIR/antigravity-ide"
    "$RM_CMD" -f "$DESKTOP_DIR/antigravity-ide.desktop"
    "$RM_CMD" -f "$ICON_FILE_IDE"

    # Clean legacy symlink ONLY if it pointed to IDE
    if [ -L "$BIN_DIR/antigravity" ]; then
        target=$(readlink "$BIN_DIR/antigravity" 2>/dev/null || true)
        case "$target" in
            *antigravity-ide*) "$RM_CMD" -f "$BIN_DIR/antigravity" ;;
        esac
    fi

    # Only wipe user profile and extensions if explicitly requested via --hard-reset
    if [ "$HARD_RESET" = true ]; then
        printf "%b\n" "${RED}[!] Hard reset: Removing Antigravity IDE settings and extensions...${RC}"
        "$RM_CMD" -rf "$HOME/.config/antigravity-ide"
        "$RM_CMD" -rf "$HOME/.cache/antigravity-ide"
        "$RM_CMD" -rf "$HOME/.antigravity-ide"
        "$RM_CMD" -rf "$HOME/.gemini/antigravity-ide"
    else
        printf "%b\n" "${GREEN}[✓] IDE settings & extensions preserved in ~/.antigravity-ide${RC}"
    fi

    # Remove residual staging folders
    for pattern in "$HOME"/antigravity-install.* "$HOME"/antigravity-ide.*; do
        [ -e "$pattern" ] && "$RM_CMD" -rf "$pattern"
    done

    printf "%b\n" "${GREEN}[✓] Antigravity IDE cleanup complete${RC}"
}

clean_shell_env_cli() {
    for rc in "$HOME/.bashrc" "$HOME/.bash_profile" "$HOME/.profile" "$HOME/.zshrc"; do
        if [ -f "$rc" ]; then
            sed -i '/# Added by Antigravity CLI installer/{n;d}' "$rc" 2>/dev/null || true
            sed -i '/# Added by Antigravity CLI installer/d' "$rc" 2>/dev/null || true
        fi
    done
}

clean_cli() {
    printf "%b\n" "${YELLOW}[*] Cleaning Antigravity CLI binary...${RC}"
    "$RM_CMD" -f "$BIN_DIR/agy"
    "$RM_CMD" -f "/usr/local/bin/agy" 2>/dev/null || true

    # Clear shell command lookup cache in the running process
    hash -d agy 2>/dev/null || true
    hash -r 2>/dev/null || true

    if [ "$HARD_RESET" = true ]; then
        printf "%b\n" "${RED}[!] Hard reset: Removing CLI configuration, history and shell entries...${RC}"
        "$RM_CMD" -rf "$HOME/.gemini/antigravity-cli"
        clean_shell_env_cli
    else
        printf "%b\n" "${GREEN}[✓] CLI configuration preserved in ~/.gemini/antigravity-cli${RC}"
    fi

    printf "%b\n" "${GREEN}[✓] Antigravity CLI cleanup complete${RC}"
}

deploy_icon() {
    target_icon="$1"
    mkdir -p "$ICON_DIR"
    printf "%b\n" "${YELLOW}[*] Configuring official Google Antigravity icon...${RC}"

    # Try downloading official full-color icon from Cloudinary
    if curl -fsSL --retry 3 "$ICON_URL" -o "$target_icon" 2>/dev/null; then
        printf "%b\n" "${GREEN}[✓] Official icon saved: $target_icon${RC}"
        return 0
    fi

    # Fallback to local bundled asset in linutil repository
    if [ -f "$ASSET_ICON" ]; then
        cp "$ASSET_ICON" "$target_icon"
        printf "%b\n" "${GREEN}[✓] Bundled icon saved: $target_icon${RC}"
        return 0
    fi

    # Fallback to bundled package icon
    bundled_pkg_icon=$(find "$APP_DIR" "$IDE_DIR" -iname "*antigravity*.png" 2>/dev/null | head -1)
    if [ -n "$bundled_pkg_icon" ] && [ -f "$bundled_pkg_icon" ]; then
        cp "$bundled_pkg_icon" "$target_icon"
        printf "%b\n" "${GREEN}[✓] Package icon saved: $target_icon${RC}"
        return 0
    fi

    printf "%b\n" "${YELLOW}[~] Icon download skipped, fallback to default${RC}"
}

# ── Installation Functions ───────────────────────────────────────────────────
install_agent_app() {
    detect_arch
    stop_app_processes
    clean_agent_app

    printf "%b\n" "${CYAN}━━━ Installing Antigravity Desktop App v${VERSION_APP} ━━━━━━━━━━━━━━━━━${RC}"
    URL="https://storage.googleapis.com/antigravity-public/antigravity-hub/${VERSION_APP}-${BUILD_APP}/${PLATFORM}/Antigravity.tar.gz"

    STAGE=$(mktemp -d "$HOME/antigravity-app.XXXXXX")
    trap '"$RM_CMD" -rf -- "$STAGE"' EXIT INT TERM

    printf "%b\n" "${YELLOW}[1/4] Acquiring Antigravity App archive...${RC}"
    acquire_archive "$URL" "$STAGE/Antigravity.tar.gz" "Antigravity.tar.gz" "Antigravity" || exit 1

    printf "%b\n" "${YELLOW}[2/4] Extracting payload...${RC}"
    mkdir -p "$STAGE/extract"
    tar -xzf "$STAGE/Antigravity.tar.gz" -C "$STAGE/extract"

    SOURCE_BIN=$(find "$STAGE/extract" \( -type f -o -type l \) -iname 'Antigravity' | head -1)
    if [ -z "$SOURCE_BIN" ] || [ ! -f "$SOURCE_BIN" ]; then
        printf "%b\n" "${RED}[✗] Antigravity executable not found inside archive.${RC}"
        printf "%b\n" "${YELLOW}Archive contents (first 30 entries):${RC}"
        tar -tzf "$STAGE/Antigravity.tar.gz" 2>/dev/null | head -30
        exit 1
    fi

    chmod u+x "$SOURCE_BIN"
    BIN_REL="${SOURCE_BIN#"$STAGE/extract/"}"

    printf "%b\n" "${YELLOW}[3/4] Deploying to $APP_DIR...${RC}"
    mkdir -p "$HOME/.local" "$BIN_DIR" "$DESKTOP_DIR" "$STATE_DIR"
    mv "$STAGE/extract" "$APP_DIR"

    APP_BIN="$APP_DIR/$BIN_REL"
    chmod u+x "$APP_BIN"

    # Dedicated Terminal Launcher: always executes Desktop App
    cat > "$BIN_DIR/antigravity" <<EOF
#!/usr/bin/env bash
exec "$APP_BIN" "\$@"
EOF
    chmod +x "$BIN_DIR/antigravity"

    printf '%s\n' "$VERSION_APP" > "$APP_DIR/.release-version"

    # Configure Icon
    deploy_icon "$ICON_FILE_APP"

    # Desktop Entry with explicit StartupWMClass to prevent WM grouping collisions
    printf "%b\n" "${YELLOW}[4/4] Configuring desktop integration...${RC}"
    cat > "$DESKTOP_DIR/antigravity.desktop" <<EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=Antigravity
Comment=Google Antigravity Agent Workspace
Exec=$BIN_DIR/antigravity %U
TryExec=$BIN_DIR/antigravity
Icon=$ICON_FILE_APP
Terminal=false
Categories=Development;Utility;
StartupNotify=true
StartupWMClass=Antigravity
EOF
    chmod 644 "$DESKTOP_DIR/antigravity.desktop"

    if command -v update-desktop-database >/dev/null 2>&1; then
        update-desktop-database "$DESKTOP_DIR" 2>/dev/null || true
    fi
    if command -v gtk-update-icon-cache >/dev/null 2>&1; then
        gtk-update-icon-cache -f -t "$HOME/.local/share/icons/hicolor" 2>/dev/null || true
    fi

    # Cleanup temporary stage
    "$RM_CMD" -rf -- "$STAGE"
    trap - EXIT INT TERM

    print_app_summary
}

install_ide() {
    detect_arch
    stop_ide_processes
    clean_ide

    printf "%b\n" "${CYAN}━━━ Installing Antigravity IDE v${VERSION_IDE} ━━━━━━━━━━━━━━━━━━━━━━━${RC}"
    URL="https://edgedl.me.gvt1.com/edgedl/release2/j0qc3/antigravity/stable/${VERSION_IDE}-${BUILD_IDE}/${PLATFORM}/Antigravity%20IDE.tar.gz"

    STAGE=$(mktemp -d "$HOME/antigravity-ide.XXXXXX")
    trap '"$RM_CMD" -rf -- "$STAGE"' EXIT INT TERM

    printf "%b\n" "${YELLOW}[1/4] Acquiring Antigravity IDE archive...${RC}"
    acquire_archive "$URL" "$STAGE/Antigravity-IDE.tar.gz" "Antigravity IDE.tar.gz" "antigravity-ide" || exit 1

    printf "%b\n" "${YELLOW}[2/4] Extracting payload...${RC}"
    mkdir -p "$STAGE/extract"
    tar -xzf "$STAGE/Antigravity-IDE.tar.gz" -C "$STAGE/extract"

    NEW_BIN=$(find "$STAGE/extract" \( -type f -o -type l \) -name 'antigravity-ide' | head -1)
    if [ -z "$NEW_BIN" ]; then
        printf "%b\n" "${RED}[✗] antigravity-ide executable not found inside archive.${RC}"
        printf "%b\n" "${YELLOW}Archive contents (first 30 entries):${RC}"
        tar -tzf "$STAGE/Antigravity-IDE.tar.gz" 2>/dev/null | head -30
        exit 1
    fi

    NEW_ROOT="$(dirname "$NEW_BIN")"
    while [ "$NEW_ROOT" != "$STAGE/extract" ] && [ ! -f "$NEW_ROOT/resources/app/product.json" ]; do
        parent="$(dirname "$NEW_ROOT")"
        [ "$parent" = "$NEW_ROOT" ] && break
        NEW_ROOT="$parent"
    done

    printf "%b\n" "${YELLOW}[3/4] Deploying to $IDE_DIR...${RC}"
    mkdir -p "$HOME/.local" "$BIN_DIR" "$DESKTOP_DIR"
    mv "$NEW_ROOT" "$IDE_DIR"
    chmod +x "$IDE_DIR/antigravity-ide"

    # Dedicated Terminal Launcher: always executes IDE
    ln -sf "$IDE_DIR/antigravity-ide" "$BIN_DIR/antigravity-ide"

    printf '%s\n' "$VERSION_IDE" > "$IDE_DIR/antigravity-release-version"

    # Configure Icon
    deploy_icon "$ICON_FILE_IDE"

    # Desktop Entry with explicit StartupWMClass
    printf "%b\n" "${YELLOW}[4/4] Configuring desktop integration...${RC}"
    cat > "$DESKTOP_DIR/antigravity-ide.desktop" <<EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=Antigravity IDE
Comment=Google Antigravity standalone development environment
Exec=$BIN_DIR/antigravity-ide %F
TryExec=$BIN_DIR/antigravity-ide
Icon=$ICON_FILE_IDE
Terminal=false
Categories=Development;IDE;TextEditor;
StartupNotify=true
StartupWMClass=antigravity-ide
EOF
    chmod 644 "$DESKTOP_DIR/antigravity-ide.desktop"

    if command -v update-desktop-database >/dev/null 2>&1; then
        update-desktop-database "$DESKTOP_DIR" 2>/dev/null || true
    fi
    if command -v gtk-update-icon-cache >/dev/null 2>&1; then
        gtk-update-icon-cache -f -t "$HOME/.local/share/icons/hicolor" 2>/dev/null || true
    fi

    "$RM_CMD" -rf -- "$STAGE"
    trap - EXIT INT TERM

    print_ide_summary
}

install_cli() {
    stop_cli_processes
    clean_cli

    printf "%b\n" "${CYAN}━━━ Installing Antigravity CLI (\`agy\`) ━━━━━━━━━━━━━━━━━━━━━━━━━${RC}"
    printf "%b\n" "${YELLOW}[*] Running official Google installer...${RC}"
    curl -fsSL https://antigravity.google/cli/install.sh | bash

    if command -v agy >/dev/null 2>&1; then
        printf "%b\n" "${GREEN}[✓] Antigravity CLI successfully installed at: $(command -v agy)${RC}"
    elif [ -x "$HOME/.local/bin/agy" ]; then
        printf "%b\n" "${GREEN}[✓] Antigravity CLI installed in $HOME/.local/bin/agy${RC}"
    else
        printf "%b\n" "${YELLOW}[~] Antigravity CLI installed. Ensure $BIN_DIR is in your PATH.${RC}"
    fi

    echo ""
    printf "%b\n" "${GREEN}=================================================================${RC}"
    printf "%b\n" "${GREEN}  Antigravity CLI Installation Complete!                        ${RC}"
    printf "%b\n" "${CYAN}  Launch: agy                                                    ${RC}"
    printf "%b\n" "${GREEN}=================================================================${RC}"
}

uninstall_cli() {
    stop_cli_processes
    clean_cli
    clean_shell_env_cli

    hash -d agy 2>/dev/null || true
    hash -r 2>/dev/null || true

    echo ""
    printf "%b\n" "${GREEN}=================================================================${RC}"
    printf "%b\n" "${GREEN}  Antigravity CLI Removed Successfully                          ${RC}"
    printf "%b\n" "${GREEN}=================================================================${RC}"
    printf "%b\n" "${CYAN}-----------------------------------------------------------------${RC}"
    printf "%b\n" "${YELLOW}[!] Shell Command Cache Notice:${RC}"
    printf "%b\n" "${CYAN}    If you ran 'agy' previously in this open terminal session,   ${RC}"
    printf "%b\n" "${CYAN}    Bash remembers command locations in its internal hash table. ${RC}"
    printf "%b\n" "${CYAN}    To clear the cached location immediately in this terminal:   ${RC}"
    printf "%b\n" "${GREEN}      hash -d agy${RC}"
    printf "%b\n" "${CYAN}    Or simply open a new terminal window / tab.                  ${RC}"
    printf "%b\n" "${CYAN}-----------------------------------------------------------------${RC}"
    echo ""
}

uninstall_ide() {
    stop_ide_processes
    clean_ide
    echo ""
    printf "%b\n" "${GREEN}[✓] Antigravity IDE uninstalled successfully.${RC}"
    echo ""
}

uninstall_agent_app() {
    stop_app_processes
    clean_agent_app
    echo ""
    printf "%b\n" "${GREEN}[✓] Antigravity Desktop App uninstalled successfully.${RC}"
    echo ""
}

manage_cli() {
    if command -v agy >/dev/null 2>&1 || [ -x "$BIN_DIR/agy" ]; then
        printf "%b\n" "${CYAN}-----------------------------------------------------------------${RC}"
        printf "%b\n" "${GREEN}Antigravity CLI is currently installed: $(command -v agy 2>/dev/null || echo "$BIN_DIR/agy")${RC}"
        printf "%b\n" "${YELLOW}  1) Reinstall / Update Antigravity CLI${RC}"
        printf "%b\n" "${RED}  2) Uninstall / Remove Antigravity CLI${RC}"
        printf "%b\n" "${CYAN}  3) Back / Abort${RC}"
        printf "%b\n" "${CYAN}-----------------------------------------------------------------${RC}"
        printf "%b" "${YELLOW}Choose an action [1-3, default 1]: ${RC}"
        read -r CLI_CHOICE
        CLI_CHOICE="${CLI_CHOICE:-1}"
        case "$CLI_CHOICE" in
            1) install_cli ;;
            2) uninstall_cli ;;
            3) printf "%b\n" "${YELLOW}Operation cancelled.${RC}"; return 0 ;;
            *) printf "%b\n" "${RED}Invalid choice: $CLI_CHOICE${RC}"; return 1 ;;
        esac
    else
        install_cli
    fi
}

show_uninstall_menu() {
    printf "%b\n" "${CYAN}=================================================================${RC}"
    printf "%b\n" "${YELLOW}               Uninstall Antigravity Components                  ${RC}"
    printf "%b\n" "${CYAN}=================================================================${RC}"
    printf "%b\n" "${YELLOW}  1) Uninstall Antigravity CLI (\`agy\`)${RC}"
    printf "%b\n" "${YELLOW}  2) Uninstall Antigravity IDE${RC}"
    printf "%b\n" "${YELLOW}  3) Uninstall Antigravity Desktop App${RC}"
    printf "%b\n" "${RED}  4) Uninstall Everything (Factory Reset)${RC}"
    printf "%b\n" "${CYAN}  5) Back to Main Menu${RC}"
    printf "%b\n" "${CYAN}=================================================================${RC}"
    printf "%b" "${YELLOW}Select component to uninstall [1-5]: ${RC}"
    read -r UN_CHOICE
    case "$UN_CHOICE" in
        1) uninstall_cli ;;
        2) uninstall_ide ;;
        3) uninstall_agent_app ;;
        4) factory_reset_all ;;
        5) show_menu ;;
        *) printf "%b\n" "${RED}Invalid choice: $UN_CHOICE${RC}"; return 1 ;;
    esac
}

install_all() {
    install_agent_app
    install_ide
    install_cli

    echo ""
    printf "%b\n" "${GREEN}=================================================================${RC}"
    printf "%b\n" "${GREEN}  Full Google Antigravity Suite Configured for Coexistence!      ${RC}"
    printf "%b\n" "${CYAN}  • Desktop Agent Workspace: antigravity                        ${RC}"
    printf "%b\n" "${CYAN}  • Standalone IDE:          antigravity-ide                    ${RC}"
    printf "%b\n" "${CYAN}  • Command Line Interface:  agy                                ${RC}"
    printf "%b\n" "${GREEN}=================================================================${RC}"
}

factory_reset_all() {
    printf "%b\n" "${RED}=================================================================${RC}"
    printf "%b\n" "${RED}  WARNING: FACTORY RESET (Wipes all logins, caches & extensions) ${RC}"
    printf "%b\n" "${RED}=================================================================${RC}"
    printf "%b" "${YELLOW}Are you sure you want to perform a complete wipe? (y/N): ${RC}"
    read -r CONFIRM
    case "$CONFIRM" in
        [yY]|[yY][eE][sS])
            HARD_RESET=true
            stop_all_processes
            clean_agent_app
            clean_ide
            clean_cli
            printf "%b\n" "${GREEN}[✓] All Antigravity installations and user data wiped.${RC}"
            ;;
        *)
            printf "%b\n" "${YELLOW}Factory reset aborted.${RC}"
            ;;
    esac
}

# ── Summary Display ──────────────────────────────────────────────────────────
print_app_summary() {
    echo ""
    printf "%b\n" "${GREEN}=================================================================${RC}"
    printf "%b\n" "${YELLOW}         Google Antigravity App Installation Complete             ${RC}"
    printf "%b\n" "${GREEN}=================================================================${RC}"
    printf "%b\n" "| Component              | Status                               |"
    printf "%b\n" "| ---------------------- | ------------------------------------ |"
    printf "%b\n" "| Google Antigravity App | ${VERSION_APP} installed                      |"
    printf "%b\n" "| Architecture           | ${PLATFORM}                             |"
    printf "%b\n" "| Terminal launcher      | ~/.local/bin/antigravity             |"
    printf "%b\n" "| Desktop entry          | ~/.local/share/applications/         |"
    printf "%b\n" "| StartupWMClass         | Antigravity                          |"
    printf "%b\n" "${GREEN}=================================================================${RC}"
    echo ""
    printf "%b\n" "${CYAN}Launch anytime:${RC}"
    printf "%b\n" "${GREEN}  antigravity${RC}"
    echo ""
}

print_ide_summary() {
    echo ""
    printf "%b\n" "${GREEN}=================================================================${RC}"
    printf "%b\n" "${YELLOW}         Antigravity IDE Installation Complete                   ${RC}"
    printf "%b\n" "${GREEN}=================================================================${RC}"
    printf "%b\n" "| Component              | Status                               |"
    printf "%b\n" "| ---------------------- | ------------------------------------ |"
    printf "%b\n" "| Antigravity IDE        | ${VERSION_IDE} installed                      |"
    printf "%b\n" "| Architecture           | ${PLATFORM}                             |"
    printf "%b\n" "| Terminal launcher      | ~/.local/bin/antigravity-ide         |"
    printf "%b\n" "| Desktop entry          | ~/.local/share/applications/         |"
    printf "%b\n" "| StartupWMClass         | antigravity-ide                      |"
    printf "%b\n" "${GREEN}=================================================================${RC}"
    echo ""
    printf "%b\n" "${CYAN}Launch anytime:${RC}"
    printf "%b\n" "${GREEN}  antigravity-ide${RC}"
    echo ""
}

# ── Interactive Menu ─────────────────────────────────────────────────────────
show_menu() {
    clear 2>/dev/null || true
    printf "%b\n" "${CYAN}=================================================================${RC}"
    printf "%b\n" "${YELLOW}               Google Antigravity Suite Manager                  ${RC}"
    printf "%b\n" "${CYAN}=================================================================${RC}"
    printf "%b\n" "${GREEN}  1) Antigravity IDE       - Standalone AI Code Editor (v${VERSION_IDE})${RC}"
    printf "%b\n" "${GREEN}  2) Antigravity Agent/App - Google Antigravity App Workspace (v${VERSION_APP})${RC}"
    printf "%b\n" "${GREEN}  3) Antigravity CLI       - Manage \`agy\` Terminal CLI (Install/Remove)${RC}"
    printf "%b\n" "${GREEN}  4) All / Coexist Suite   - Setup App, IDE & CLI together side-by-side${RC}"
    printf "%b\n" "${YELLOW}  5) Uninstall Options     - Choose specific component to remove${RC}"
    printf "%b\n" "${RED}  6) Factory Reset         - Wipe all Antigravity data & saved logins${RC}"
    printf "%b\n" "${CYAN}  7) Abort${RC}"
    printf "%b\n" "${CYAN}=================================================================${RC}"
    printf "%b" "${YELLOW}Which tool do you want to manage? [1-7, default 4]: ${RC}"
    read -r CHOICE
    CHOICE="${CHOICE:-4}"

    case "$CHOICE" in
        1) install_ide ;;
        2) install_agent_app ;;
        3) manage_cli ;;
        4) install_all ;;
        5) show_uninstall_menu ;;
        6) factory_reset_all ;;
        7) printf "%b\n" "${YELLOW}Installation aborted by user.${RC}"; exit 0 ;;
        *) printf "%b\n" "${RED}Invalid choice: $CHOICE${RC}"; exit 1 ;;
    esac
}

# ── Main Entry ───────────────────────────────────────────────────────────────
# Check for optional --hard-reset flag anywhere in args
for arg in "$@"; do
    case "$arg" in
        --hard-reset|--clean)
            HARD_RESET=true
            ;;
    esac
done

case "${1:-}" in
    --ide)
        case "${2:-}" in
            --remove|--uninstall) uninstall_ide ;;
            *) install_ide ;;
        esac
        ;;
    --agent|--app)
        case "${2:-}" in
            --remove|--uninstall) uninstall_agent_app ;;
            *) install_agent_app ;;
        esac
        ;;
    --cli)
        case "${2:-}" in
            --remove|--uninstall) uninstall_cli ;;
            --install|--update) install_cli ;;
            *) manage_cli ;;
        esac
        ;;
    --uninstall-cli|--remove-cli)
        uninstall_cli
        ;;
    --uninstall-ide|--remove-ide)
        uninstall_ide
        ;;
    --uninstall-app|--remove-app)
        uninstall_agent_app
        ;;
    --all)
        install_all
        ;;
    --hard-reset|--clean)
        factory_reset_all
        ;;
    *)
        show_menu
        ;;
esac
