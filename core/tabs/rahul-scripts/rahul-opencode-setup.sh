#!/bin/sh -e

# Description: Install and optimize OpenCode CLI + Desktop for RahulOS
# Works on: Arch, Debian, Fedora, openSUSE, Void, Alpine, Solus

. ../common-script.sh

checkEnv

APP_NAME="OpenCode Desktop"
APPIMAGE_NAME="opencode-desktop.AppImage"
APP_DIR="${OPENCODE_DESKTOP_APP_DIR:-$HOME/Applications}"
APPIMAGE_PATH="$APP_DIR/$APPIMAGE_NAME"
BIN_DIR="${XDG_BIN_DIR:-$HOME/.local/bin}"
BIN_PATH="$BIN_DIR/opencode-desktop"
DESKTOP_DIR="$HOME/.local/share/applications"
DESKTOP_FILE="$DESKTOP_DIR/opencode-desktop.desktop"
ICON_DIR="$HOME/.local/share/icons/hicolor/scalable/apps"
ICON_FILE="$ICON_DIR/opencode-desktop.svg"
RAHULOS_VAULT="${RAHULOS_VAULT:-$HOME/.work}"
RAHULOS_WORKSPACE="${RAHULOS_WORKSPACE:-$HOME/work}"
NPM_GLOBAL="$HOME/.npm-global"

clear 2>/dev/null || true
printf "%b\n" "${CYAN}=================================================================${RC}"
printf "%b\n" "${YELLOW}        Rahul's OpenCode CLI + Desktop Setup                     ${RC}"
printf "%b\n" "${CYAN}=================================================================${RC}"
printf "%b\n" "${GREEN}  - Installs OpenCode terminal CLI${RC}"
printf "%b\n" "${GREEN}  - Installs Desktop AppImage under ~/Applications${RC}"
printf "%b\n" "${GREEN}  - Creates fast launcher: ~/.local/bin/opencode-desktop${RC}"
printf "%b\n" "${GREEN}  - Adds rofi/dmenu desktop entry with icon${RC}"
printf "%b\n" "${GREEN}  - Uses RahulOS paths: $RAHULOS_VAULT and $RAHULOS_WORKSPACE${RC}"
printf "%b\n" "${CYAN}=================================================================${RC}"
echo ""

install_pkg_if_missing() {
    cmd="$1"
    pkg="$2"

    if command_exists "$cmd"; then
        printf "%b\n" "${GREEN}[✓] $cmd already installed${RC}"
        return
    fi

    printf "%b\n" "${YELLOW}[*] Installing $pkg...${RC}"
    case "$PACKAGER" in
        pacman)
            "$ESCALATION_TOOL" "$PACKAGER" -S --needed --noconfirm "$pkg"
            ;;
        apk)
            "$ESCALATION_TOOL" "$PACKAGER" add "$pkg"
            ;;
        xbps-install)
            "$ESCALATION_TOOL" "$PACKAGER" -Sy "$pkg"
            ;;
        nala|apt-get|apt)
            "$ESCALATION_TOOL" apt-get update
            "$ESCALATION_TOOL" apt-get install -y "$pkg"
            ;;
        dnf|zypper|eopkg)
            "$ESCALATION_TOOL" "$PACKAGER" install -y "$pkg"
            ;;
        *)
            printf "%b\n" "${RED}[✗] Cannot install $pkg automatically.${RC}"
            exit 1
            ;;
    esac
}

setup_npm_global() {
    if [ "$(id -u)" = "0" ]; then
        return
    fi

    mkdir -p "$NPM_GLOBAL/bin"
    npm config set prefix "$NPM_GLOBAL" >/dev/null 2>&1 || true

    case ":$PATH:" in
        *:"$NPM_GLOBAL/bin":*) ;;
        *) export PATH="$NPM_GLOBAL/bin:$PATH" ;;
    esac
}

install_dependencies() {
    install_pkg_if_missing curl curl
    install_pkg_if_missing bash bash
    install_pkg_if_missing node nodejs
    install_pkg_if_missing npm npm

    if ! command_exists rofi; then
        printf "%b\n" "${YELLOW}[*] rofi is not installed; installing so the launcher appears in drun.${RC}"
        install_pkg_if_missing rofi rofi
    else
        printf "%b\n" "${GREEN}[✓] rofi already installed${RC}"
    fi

    if ! command_exists update-desktop-database; then
        case "$PACKAGER" in
            pacman) install_pkg_if_missing update-desktop-database desktop-file-utils ;;
            apk) install_pkg_if_missing update-desktop-database desktop-file-utils ;;
            xbps-install) install_pkg_if_missing update-desktop-database desktop-file-utils ;;
            nala|apt-get|apt) install_pkg_if_missing update-desktop-database desktop-file-utils ;;
            dnf|zypper|eopkg) install_pkg_if_missing update-desktop-database desktop-file-utils ;;
            *) printf "%b\n" "${YELLOW}[~] desktop-file-utils not auto-installed on this distro.${RC}" ;;
        esac
    else
        printf "%b\n" "${GREEN}[✓] desktop-file-utils already installed${RC}"
    fi
}

install_opencode_cli() {
    printf "\n%b\n" "${CYAN}━━━ OpenCode CLI ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RC}"

    if command_exists opencode; then
        printf "%b\n" "${GREEN}[✓] opencode CLI already installed — $(opencode --version 2>/dev/null || echo installed)${RC}"
        return
    fi

    if [ "$PACKAGER" = "pacman" ]; then
        printf "%b\n" "${YELLOW}[*] Installing OpenCode CLI from Arch package repo...${RC}"
        "$ESCALATION_TOOL" pacman -S --needed --noconfirm opencode || {
            printf "%b\n" "${YELLOW}[~] pacman install failed; falling back to npm.${RC}"
            setup_npm_global
            npm install -g opencode-ai@latest
        }
    else
        printf "%b\n" "${YELLOW}[*] Installing OpenCode CLI with npm...${RC}"
        setup_npm_global
        npm install -g opencode-ai@latest
    fi

    if command_exists opencode; then
        printf "%b\n" "${GREEN}[✓] opencode CLI installed — $(opencode --version 2>/dev/null || echo installed)${RC}"
    else
        printf "%b\n" "${YELLOW}[~] opencode installed, but your shell PATH may need a restart.${RC}"
        printf "%b\n" "${CYAN}    Expected npm bin: $NPM_GLOBAL/bin${RC}"
    fi
}

find_local_appimage() {
    for candidate in \
        "$HOME/opencode-desktop-linux-x86_64.AppImage" \
        "$HOME/Downloads/opencode-desktop-linux-x86_64.AppImage" \
        "$HOME/Downloads/opencode-desktop.AppImage" \
        "$APPIMAGE_PATH"
    do
        if [ -f "$candidate" ]; then
            printf "%s" "$candidate"
            return 0
        fi
    done

    return 1
}

download_appimage() {
    tmp_file="$APPIMAGE_PATH.download"
    api_url="https://api.github.com/repos/sst/opencode/releases/latest"

    printf "%b\n" "${YELLOW}[*] Downloading latest OpenCode Desktop AppImage...${RC}"
    download_url="$(curl -fsSL "$api_url" \
        | sed -n 's/.*"browser_download_url": "\(.*opencode-desktop-linux-x86_64\.AppImage\)".*/\1/p' \
        | head -n 1)"

    if [ -z "$download_url" ]; then
        api_url="https://api.github.com/repos/anomalyco/opencode/releases/latest"
        download_url="$(curl -fsSL "$api_url" \
            | sed -n 's/.*"browser_download_url": "\(.*opencode-desktop-linux-x86_64\.AppImage\)".*/\1/p' \
            | head -n 1)"
    fi

    if [ -z "$download_url" ]; then
        printf "%b\n" "${RED}[✗] Could not discover latest AppImage from GitHub releases.${RC}"
        printf "%b\n" "${YELLOW}    Download it manually from https://opencode.ai/download and rerun this script.${RC}"
        exit 1
    fi

    curl -fL "$download_url" -o "$tmp_file"
    mv "$tmp_file" "$APPIMAGE_PATH"
}

install_desktop_appimage() {
    printf "\n%b\n" "${CYAN}━━━ OpenCode Desktop AppImage ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RC}"

    mkdir -p "$APP_DIR" "$BIN_DIR" "$DESKTOP_DIR" "$ICON_DIR" "$RAHULOS_VAULT" "$RAHULOS_WORKSPACE"

    if [ -n "${OPENCODE_DESKTOP_APPIMAGE_SRC:-}" ]; then
        if [ ! -f "$OPENCODE_DESKTOP_APPIMAGE_SRC" ]; then
            printf "%b\n" "${RED}[✗] OPENCODE_DESKTOP_APPIMAGE_SRC does not exist: $OPENCODE_DESKTOP_APPIMAGE_SRC${RC}"
            exit 1
        fi
        printf "%b\n" "${YELLOW}[*] Installing AppImage from OPENCODE_DESKTOP_APPIMAGE_SRC${RC}"
        cp "$OPENCODE_DESKTOP_APPIMAGE_SRC" "$APPIMAGE_PATH"
    elif [ -f "$APPIMAGE_PATH" ]; then
        printf "%b\n" "${GREEN}[✓] AppImage already installed: $APPIMAGE_PATH${RC}"
    elif local_appimage="$(find_local_appimage)"; then
        printf "%b\n" "${YELLOW}[*] Moving local AppImage from $local_appimage${RC}"
        mv "$local_appimage" "$APPIMAGE_PATH"
    else
        download_appimage
    fi

    chmod +x "$APPIMAGE_PATH"
    printf "%b\n" "${GREEN}[✓] Desktop AppImage ready: $APPIMAGE_PATH${RC}"
}

write_icon() {
    cat > "$ICON_FILE" <<'EOF'
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 128 128">
  <rect width="128" height="128" rx="24" fill="#111827"/>
  <path d="M30 38h68c7.7 0 14 6.3 14 14v38c0 7.7-6.3 14-14 14H30c-7.7 0-14-6.3-14-14V52c0-7.7 6.3-14 14-14z" fill="#0f172a" stroke="#38bdf8" stroke-width="4"/>
  <path d="M36 61l16 11-16 11" fill="none" stroke="#a7f3d0" stroke-width="8" stroke-linecap="round" stroke-linejoin="round"/>
  <path d="M63 85h30" fill="none" stroke="#f8fafc" stroke-width="8" stroke-linecap="round"/>
  <circle cx="99" cy="31" r="13" fill="#38bdf8"/>
  <path d="M96 25l9 6-9 6z" fill="#111827"/>
</svg>
EOF
    printf "%b\n" "${GREEN}[✓] Icon installed: $ICON_FILE${RC}"
}

write_fast_wrapper() {
    cat > "$BIN_PATH" <<EOF
#!/usr/bin/env bash
set -euo pipefail

# Fast OpenCode Desktop profile generated by linutil Rahul scripts.
# Override with RAHULOS_VAULT / RAHULOS_WORKSPACE before launching if needed.
RAHULOS_VAULT="\${RAHULOS_VAULT:-$RAHULOS_VAULT}"
RAHULOS_WORKSPACE="\${RAHULOS_WORKSPACE:-$RAHULOS_WORKSPACE}"
mkdir -p "\$RAHULOS_VAULT" "\$RAHULOS_WORKSPACE"

export OPENCODE_CONFIG_CONTENT=\$(cat <<JSON
{
  "\$schema": "https://opencode.ai/config.json",
  "autoupdate": "notify",
  "watcher": {
    "ignore": [
      "**/node_modules/**",
      "**/.git/**",
      "**/dist/**",
      "**/build/**",
      "**/.next/**",
      "**/coverage/**",
      "**/.cache/**",
      "**/target/**",
      "**/.venv/**",
      "**/__pycache__/**"
    ]
  },
  "mcp": {
    "filesystem-rahulos": {
      "type": "local",
      "command": ["npx", "-y", "@modelcontextprotocol/server-filesystem", "\$RAHULOS_VAULT", "\$RAHULOS_WORKSPACE"],
      "enabled": true
    },
    "fetch": { "enabled": false },
    "git": { "enabled": false },
    "context7": { "enabled": false },
    "desktop-commander-local": { "enabled": false },
    "playwright": { "enabled": false },
    "open-websearch": { "enabled": false },
    "sqlite": { "enabled": false },
    "memory": { "enabled": false },
    "carbone-mcp": { "enabled": false },
    "github": { "enabled": false },
    "oci-memory-cloudflare": { "enabled": false }
  }
}
JSON
)

exec "$APPIMAGE_PATH" "\$@"
EOF

    chmod +x "$BIN_PATH"
    printf "%b\n" "${GREEN}[✓] Fast launcher written: $BIN_PATH${RC}"
}

write_desktop_entry() {
    cat > "$DESKTOP_FILE" <<EOF
[Desktop Entry]
Type=Application
Name=$APP_NAME
Comment=OpenCode AI coding agent desktop app
Exec=$BIN_PATH
Icon=$ICON_FILE
Terminal=false
Categories=Development;IDE;
StartupNotify=true
StartupWMClass=opencode
EOF

    if command_exists update-desktop-database; then
        update-desktop-database "$DESKTOP_DIR" >/dev/null 2>&1 || true
    fi

    printf "%b\n" "${GREEN}[✓] Rofi launcher written: $DESKTOP_FILE${RC}"
}

verify_setup() {
    printf "\n%b\n" "${CYAN}━━━ Verification ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RC}"

    test -x "$APPIMAGE_PATH"
    test -x "$BIN_PATH"
    test -f "$DESKTOP_FILE"
    test -f "$ICON_FILE"

    if command_exists desktop-file-validate; then
        desktop-file-validate "$DESKTOP_FILE"
        printf "%b\n" "${GREEN}[✓] Desktop entry validates${RC}"
    fi

    if command_exists bash; then
        bash -n "$BIN_PATH"
        printf "%b\n" "${GREEN}[✓] Launcher shell syntax validates${RC}"
    fi

    printf "%b\n" "${GREEN}=================================================================${RC}"
    printf "%b\n" "${GREEN}  OpenCode setup complete.${RC}"
    printf "%b\n" "${CYAN}  Terminal: opencode${RC}"
    printf "%b\n" "${CYAN}  Desktop:  opencode-desktop${RC}"
    printf "%b\n" "${CYAN}  Rofi:     rofi -show drun  →  OpenCode Desktop${RC}"
    printf "%b\n" "${GREEN}=================================================================${RC}"
}

install_dependencies
install_opencode_cli
install_desktop_appimage
write_icon
write_fast_wrapper
write_desktop_entry
verify_setup
