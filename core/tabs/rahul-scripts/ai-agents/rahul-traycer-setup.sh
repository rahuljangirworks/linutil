#!/bin/sh -e

# Description: Install/update Traycer AI (Plan → Execute → Verify Agent Platform)
# Homepage:    https://traycer.ai
# Download:    https://traycer.ai/download
# Source:      https://github.com/traycerai/traycer
# Works on:    Fedora/RHEL (RPM), Debian/Ubuntu (DEB), Arch Linux (AUR), openSUSE, and generic Linux (AppImage)
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

checkEnv

APP_NAME="Traycer AI"
APP_DESC="Agent orchestration platform for parallel AI coding agents across git worktrees"
TRAYCER_API_URL="https://api.github.com/repos/traycerai/traycer/releases/latest"
TRAYCER_WEB_URL="https://github.com/traycerai/traycer/releases/latest"
TRAYCER_FALLBACK_TAG="desktop-v1.5.3"
ASSET_ICON="$SCRIPT_DIR/../assets/traycer-logo.png"

FORCE_UPDATE=0
for arg in "$@"; do
    case "$arg" in
        --force|-f|--update|-u|-y|--yes)
            FORCE_UPDATE=1
            ;;
    esac
done

printf "%b\n" "${CYAN}=================================================================${RC}"
printf "%b\n" "${YELLOW}         Traycer AI — Linux Installer & Updater                  ${RC}"
printf "%b\n" "${CYAN}=================================================================${RC}"
printf "%b\n" "${GREEN}  - Plan → Execute → Verify: spec-driven agent platform          ${RC}"
printf "%b\n" "${GREEN}  - Run Claude Code, Codex, Cursor, Antigravity in parallel      ${RC}"
printf "%b\n" "${GREEN}  - Git worktree per agent, shared specs & peer agent messaging  ${RC}"
printf "%b\n" "${GREEN}  - Official downloads: https://traycer.ai                       ${RC}"
printf "%b\n" "${CYAN}=================================================================${RC}"
echo ""

# ── Detect Installed Version ──────────────────────────────────────────────────
detect_installed_version() {
    if command_exists traycer-desktop; then
        if command_exists rpm && (rpm -q Traycer >/dev/null 2>&1 || rpm -q traycer-desktop >/dev/null 2>&1 || rpm -q traycer >/dev/null 2>&1); then
            rpm -q Traycer --qf '%{VERSION}' 2>/dev/null || rpm -q traycer-desktop --qf '%{VERSION}' 2>/dev/null || rpm -q traycer --qf '%{VERSION}' 2>/dev/null || echo "installed"
        elif command_exists dpkg-query && (dpkg-query -W -f='${Version}' traycer-desktop >/dev/null 2>&1 || dpkg-query -W -f='${Version}' Traycer >/dev/null 2>&1 || dpkg-query -W -f='${Version}' traycer >/dev/null 2>&1); then
            dpkg-query -W -f='${Version}' traycer-desktop 2>/dev/null || dpkg-query -W -f='${Version}' Traycer 2>/dev/null || dpkg-query -W -f='${Version}' traycer 2>/dev/null || echo "installed"
        elif command_exists pacman && (pacman -Q traycer-desktop-bin >/dev/null 2>&1 || pacman -Q traycer-desktop >/dev/null 2>&1 || pacman -Q traycer >/dev/null 2>&1); then
            pacman -Q traycer-desktop-bin 2>/dev/null | awk '{print $2}' || pacman -Q traycer-desktop 2>/dev/null | awk '{print $2}' || pacman -Q traycer 2>/dev/null | awk '{print $2}'
        else
            echo "installed"
        fi
    elif [ -x "/opt/Traycer/traycer-desktop" ]; then
        if command_exists rpm && (rpm -q Traycer >/dev/null 2>&1 || rpm -q traycer-desktop >/dev/null 2>&1 || rpm -q traycer >/dev/null 2>&1); then
            rpm -q Traycer --qf '%{VERSION}' 2>/dev/null || rpm -q traycer-desktop --qf '%{VERSION}' 2>/dev/null || rpm -q traycer --qf '%{VERSION}' 2>/dev/null || echo "installed"
        elif command_exists dpkg-query && (dpkg-query -W -f='${Version}' traycer-desktop >/dev/null 2>&1 || dpkg-query -W -f='${Version}' Traycer >/dev/null 2>&1 || dpkg-query -W -f='${Version}' traycer >/dev/null 2>&1); then
            dpkg-query -W -f='${Version}' traycer-desktop 2>/dev/null || dpkg-query -W -f='${Version}' Traycer 2>/dev/null || dpkg-query -W -f='${Version}' traycer 2>/dev/null || echo "installed"
        else
            echo "installed"
        fi
    elif [ -x "$HOME/.local/share/traycer/Traycer.AppImage" ] || [ -x "$HOME/.local/bin/traycer-desktop" ] || [ -x "$HOME/.local/bin/Traycer.AppImage" ]; then
        echo "installed (appimage)"
    else
        echo ""
    fi
}

# ── Resilient Asset Discovery ────────────────────────────────────────────────
fetch_release_assets() {
    # Tier 1: GitHub API (JSON)
    api_content=$(curl -fsSL --connect-timeout 5 --max-time 10 "$TRAYCER_API_URL" 2>/dev/null || true)
    if echo "$api_content" | grep -q "browser_download_url"; then
        echo "$api_content" | sed -n 's/.*"browser_download_url"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p'
        return 0
    fi

    # Tier 2: HTTP redirect tag inspection + expanded_assets (bypasses API rate limits)
    tag=$(curl -sIL --connect-timeout 5 --max-time 10 -o /dev/null -w "%{url_effective}" "$TRAYCER_WEB_URL" 2>/dev/null | sed -e 's#.*/tag/##' -e 's#.*/##')
    if [ -n "$tag" ] && [ "$tag" != "latest" ]; then
        expanded_assets=$(curl -fsSL --connect-timeout 5 --max-time 15 "https://github.com/traycerai/traycer/releases/expanded_assets/$tag" 2>/dev/null || true)
        if [ -n "$expanded_assets" ]; then
            echo "$expanded_assets" | grep -o 'href="[^"]*"' | sed -e 's/href="//' -e 's/"//' | sed -e 's#^https://github.com##' -e 's#^#https://github.com#'
            return 0
        fi
    fi

    # Tier 3: Scrape main releases page HTML
    html_content=$(curl -fsSL --connect-timeout 5 --max-time 15 "$TRAYCER_WEB_URL" 2>/dev/null || true)
    if [ -n "$html_content" ]; then
        echo "$html_content" | grep -o 'href="[^"]*"' | sed -e 's/href="//' -e 's/"//' | grep "/traycerai/traycer/releases/download/" | sed -e 's#^https://github.com##' -e 's#^#https://github.com#'
        return 0
    fi

    return 1
}

get_asset_url() {
    pattern="$1"
    url=$(fetch_release_assets 2>/dev/null | grep -E "$pattern" | head -n 1 || true)
    if [ -n "$url" ]; then
        echo "$url"
        return 0
    fi

    # Tier 4 fallback using known tag
    tag="$TRAYCER_FALLBACK_TAG"
    case "$pattern" in
        *x86_64\.rpm*) echo "https://github.com/traycerai/traycer/releases/download/${tag}/traycer-desktop-linux-x86_64.rpm" ;;
        *amd64\.deb*) echo "https://github.com/traycerai/traycer/releases/download/${tag}/traycer-desktop-linux-amd64.deb" ;;
        *arm64\.deb*) echo "https://github.com/traycerai/traycer/releases/download/${tag}/traycer-desktop-linux-arm64.deb" ;;
        *x86_64\.AppImage*) echo "https://github.com/traycerai/traycer/releases/download/${tag}/traycer-desktop-linux-x86_64.AppImage" ;;
        *arm64\.AppImage*) echo "https://github.com/traycerai/traycer/releases/download/${tag}/traycer-desktop-linux-arm64.AppImage" ;;
        *) return 1 ;;
    esac
}

# ── Ensure CLI & Desktop Integrations ─────────────────────────────────────────
setup_integrations() {
    mkdir -p "$HOME/.local/bin"
    mkdir -p "$HOME/.local/share/applications"
    mkdir -p "$HOME/.local/share/icons/hicolor/512x512/apps"
    mkdir -p "$HOME/.config/Traycer/logs"

    # 1. User CLI symlink to traycer-desktop
    exec_target="/opt/Traycer/traycer-desktop"
    if [ ! -x "$exec_target" ]; then
        if [ -x "$HOME/.local/share/traycer/Traycer.AppImage" ]; then
            exec_target="$HOME/.local/share/traycer/Traycer.AppImage"
        elif [ -x "$HOME/.local/bin/traycer-desktop" ]; then
            exec_target="$HOME/.local/bin/traycer-desktop"
        fi
    fi

    if [ -x "$exec_target" ]; then
        ln -sf "$exec_target" "$HOME/.local/bin/traycer-desktop"
        if [ -w "/usr/local/bin" ]; then
            ln -sf "$exec_target" "/usr/local/bin/traycer-desktop" 2>/dev/null || true
        elif [ -n "$ESCALATION_TOOL" ]; then
            "$ESCALATION_TOOL" ln -sf "$exec_target" "/usr/local/bin/traycer-desktop" 2>/dev/null || true
        fi
    fi

    # 2. Friendly 'traycer' CLI command
    if command_exists npm; then
        if ! command_exists traycer; then
            printf "%b\n" "${YELLOW}[*] Installing Traycer companion CLI (@traycerai/cli) via npm...${RC}"
            if [ -n "$ESCALATION_TOOL" ] && [ ! -w "$(npm config get prefix 2>/dev/null || echo /usr)/bin" ]; then
                "$ESCALATION_TOOL" npm install -g @traycerai/cli --no-progress --no-fund --no-audit 2>/dev/null || npm install -g @traycerai/cli --no-progress --no-fund --no-audit 2>/dev/null || true
            else
                npm install -g @traycerai/cli --no-progress --no-fund --no-audit 2>/dev/null || true
            fi
        fi
    fi

    if ! command_exists traycer && [ -x "$exec_target" ]; then
        ln -sf "$exec_target" "$HOME/.local/bin/traycer"
    fi

    # 3. Ensure icon exists in standard user paths
    user_icon="$HOME/.local/share/icons/hicolor/512x512/apps/traycer-desktop.png"
    user_icon_alt="$HOME/.local/share/icons/hicolor/512x512/apps/traycer.png"
    if [ ! -f "$user_icon" ]; then
        if [ -f "/usr/share/icons/hicolor/512x512/apps/traycer-desktop.png" ]; then
            cp "/usr/share/icons/hicolor/512x512/apps/traycer-desktop.png" "$user_icon" 2>/dev/null || true
        elif [ -f "/opt/Traycer/resources/app/traycer-icon.png" ]; then
            cp "/opt/Traycer/resources/app/traycer-icon.png" "$user_icon" 2>/dev/null || true
        elif [ -f "$ASSET_ICON" ]; then
            cp "$ASSET_ICON" "$user_icon" 2>/dev/null || true
        else
            curl -fsSL "https://raw.githubusercontent.com/traycerai/traycer/main/clients/desktop/resources/bundle/icon.png" -o "$user_icon" 2>/dev/null || true
        fi
    fi
    [ -f "$user_icon" ] && cp -f "$user_icon" "$user_icon_alt" 2>/dev/null || true

    # 4. Polish Desktop Entry with proper Development;IDE; categories
    user_desktop="$HOME/.local/share/applications/traycer-desktop.desktop"
    cat > "$user_desktop" <<EOF
[Desktop Entry]
Name=Traycer
GenericName=Agent Development Environment
Comment=$APP_DESC
Exec=$exec_target %U
Terminal=false
Type=Application
Icon=traycer-desktop
StartupWMClass=traycer
MimeType=x-scheme-handler/traycer;
Categories=Development;IDE;
StartupNotify=true
EOF
    chmod 644 "$user_desktop"

    if command_exists update-desktop-database; then
        update-desktop-database "$HOME/.local/share/applications" >/dev/null 2>&1 || true
    fi
}

# ── AppImage Fallback Installer ───────────────────────────────────────────────
install_appimage() {
    printf "%b\n" "${YELLOW}[*] Installing Traycer via portable AppImage...${RC}"
    if [ "$ARCH" = "aarch64" ]; then
        app_pattern="traycer-desktop-.*[-.]arm64\.AppImage$"
    else
        app_pattern="traycer-desktop-.*[-.]x86_64\.AppImage$"
    fi

    download_url=$(get_asset_url "$app_pattern")
    if [ -z "$download_url" ]; then
        printf "%b\n" "${RED}[✗] Failed to resolve Traycer AppImage download URL.${RC}"
        exit 1
    fi

    app_dir="$HOME/.local/share/traycer"
    app_bin="$app_dir/Traycer.AppImage"
    mkdir -p "$app_dir"
    mkdir -p "$HOME/.local/bin"

    printf "%b\n" "${YELLOW}[*] Downloading Traycer AppImage...${RC}"
    printf "%b\n" "${CYAN}    URL: $download_url${RC}"
    curl -fsSL --progress-bar "$download_url" -o "$app_bin"

    chmod +x "$app_bin"
    ln -sf "$app_bin" "$HOME/.local/bin/traycer-desktop"

    setup_integrations
    printf "%b\n" "${GREEN}[✓] Traycer AppImage installed successfully to $app_bin${RC}"
}

# ── Main Installer Dispatch ───────────────────────────────────────────────────
CURRENT_VER=$(detect_installed_version)

if [ -n "$CURRENT_VER" ] && [ "$FORCE_UPDATE" -eq 0 ]; then
    printf "%b\n" "${GREEN}[✓] $APP_NAME is already installed: $CURRENT_VER${RC}"
    printf "%b" "${YELLOW}[*] Do you want to reinstall or check for update? [y/N]: ${RC}"
    if [ -t 0 ]; then
        read -r choice || choice="n"
    else
        choice="n"
    fi
    case "$choice" in
        y|Y|yes|YES)
            printf "%b\n" "${CYAN}[*] Proceeding with update...${RC}"
            ;;
        *)
            printf "%b\n" "${CYAN}Keeping current installation. Setting up integrations...${RC}"
            setup_integrations
            printf "%b\n" "${GREEN}[✓] Integrations refreshed.${RC}"
            exit 0
            ;;
    esac
fi

case "$PACKAGER" in
    pacman)
        checkAURHelper
        if [ -n "$AUR_HELPER" ]; then
            printf "%b\n" "${YELLOW}[*] Installing traycer-desktop-bin from AUR using $AUR_HELPER...${RC}"
            if "$AUR_HELPER" -S --needed --noconfirm traycer-desktop-bin; then
                setup_integrations
                printf "%b\n" "${GREEN}[✓] Traycer installed via AUR.${RC}"
            else
                printf "%b\n" "${YELLOW}[!] AUR build failed or package unavailable. Falling back to AppImage...${RC}"
                install_appimage
            fi
        else
            printf "%b\n" "${YELLOW}[!] No AUR helper found. Falling back to AppImage...${RC}"
            install_appimage
        fi
        ;;

    dnf|yum)
        printf "%b\n" "${YELLOW}[*] Resolving official RPM package from GitHub releases...${RC}"
        rpm_pattern="traycer-desktop-.*[-.]x86_64\.rpm$"

        download_url=$(get_asset_url "$rpm_pattern")
        if [ -z "$download_url" ]; then
            printf "%b\n" "${YELLOW}[!] Could not resolve RPM asset. Falling back to AppImage...${RC}"
            install_appimage
        else
            tmp_rpm=$(mktemp "${TMPDIR:-/tmp}/traycer-desktop.XXXXXX.rpm")
            trap 'rm -f "$tmp_rpm"' 0 INT TERM
            printf "%b\n" "${YELLOW}[*] Downloading RPM: $download_url${RC}"
            curl -fsSL --progress-bar "$download_url" -o "$tmp_rpm"

            printf "%b\n" "${YELLOW}[*] Installing RPM package via $PACKAGER...${RC}"
            "$ESCALATION_TOOL" "$PACKAGER" install -y "$tmp_rpm"
            rm -f "$tmp_rpm"
            trap - 0 INT TERM

            setup_integrations
            printf "%b\n" "${GREEN}[✓] Traycer installed successfully via RPM!${RC}"
        fi
        ;;

    apt-get|nala)
        printf "%b\n" "${YELLOW}[*] Resolving official DEB package from GitHub releases...${RC}"
        if [ "$ARCH" = "aarch64" ]; then
            deb_pattern="traycer-desktop-.*[-.]arm64\.deb$"
        else
            deb_pattern="traycer-desktop-.*[-.]amd64\.deb$"
        fi

        download_url=$(get_asset_url "$deb_pattern")
        if [ -z "$download_url" ]; then
            printf "%b\n" "${YELLOW}[!] Could not resolve DEB asset. Falling back to AppImage...${RC}"
            install_appimage
        else
            tmp_deb=$(mktemp "${TMPDIR:-/tmp}/traycer-desktop.XXXXXX.deb")
            trap 'rm -f "$tmp_deb"' 0 INT TERM
            printf "%b\n" "${YELLOW}[*] Downloading DEB: $download_url${RC}"
            curl -fsSL --progress-bar "$download_url" -o "$tmp_deb"

            printf "%b\n" "${YELLOW}[*] Installing DEB package...${RC}"
            if ! "$ESCALATION_TOOL" "$PACKAGER" install -y "$tmp_deb" 2>/dev/null; then
                "$ESCALATION_TOOL" dpkg -i "$tmp_deb" || "$ESCALATION_TOOL" apt-get install -f -y
            fi
            rm -f "$tmp_deb"
            trap - 0 INT TERM

            setup_integrations
            printf "%b\n" "${GREEN}[✓] Traycer installed successfully via DEB!${RC}"
        fi
        ;;

    zypper)
        printf "%b\n" "${YELLOW}[*] Resolving RPM package for openSUSE...${RC}"
        rpm_pattern="traycer-desktop-.*[-.]x86_64\.rpm$"

        download_url=$(get_asset_url "$rpm_pattern")
        if [ -z "$download_url" ]; then
            install_appimage
        else
            tmp_rpm=$(mktemp "${TMPDIR:-/tmp}/traycer-desktop.XXXXXX.rpm")
            trap 'rm -f "$tmp_rpm"' 0 INT TERM
            printf "%b\n" "${YELLOW}[*] Downloading RPM: $download_url${RC}"
            curl -fsSL --progress-bar "$download_url" -o "$tmp_rpm"

            printf "%b\n" "${YELLOW}[*] Installing RPM via zypper...${RC}"
            "$ESCALATION_TOOL" zypper --non-interactive install --allow-unsigned-rpm "$tmp_rpm"
            rm -f "$tmp_rpm"
            trap - 0 INT TERM

            setup_integrations
            printf "%b\n" "${GREEN}[✓] Traycer installed successfully via zypper!${RC}"
        fi
        ;;

    *)
        printf "%b\n" "${YELLOW}[*] Unsupported direct package manager ($PACKAGER). Using AppImage installer...${RC}"
        install_appimage
        ;;
esac

echo ""
printf "%b\n" "${GREEN}=================================================================${RC}"
printf "%b\n" "${GREEN}  ✅  Traycer AI setup complete!                                 ${RC}"
printf "%b\n" "${CYAN}=================================================================${RC}"
printf "%b\n" "${YELLOW}  Launch options:${RC}"
printf "%b\n" "${CYAN}    Desktop   → App Menu / Search 'Traycer'                      ${RC}"
printf "%b\n" "${CYAN}    Terminal  → 'traycer-desktop' or 'traycer'                   ${RC}"
printf "%b\n" "${CYAN}=================================================================${RC}"
echo ""
