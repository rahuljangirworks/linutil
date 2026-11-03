#!/bin/sh -e

# Description: Install/update Orca ADE (Agent Development Environment)
# Homepage:    https://onorca.dev
# Download:    https://www.onorca.dev/download/started?platform=linux
# Source:      https://github.com/stablyai/orca
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

APP_NAME="Orca ADE"
APP_DESC="Agent Development Environment for parallel AI coding agents"
ORCA_API_URL="https://api.github.com/repos/stablyai/orca/releases/latest"
ORCA_WEB_URL="https://github.com/stablyai/orca/releases/latest"
ORCA_FALLBACK_TAG="v1.4.247"
ASSET_ICON="$SCRIPT_DIR/../assets/orca-logo.png"

FORCE_UPDATE=0
for arg in "$@"; do
    case "$arg" in
        --force|-f|--update|-u|-y|--yes)
            FORCE_UPDATE=1
            ;;
    esac
done

printf "%b\n" "${CYAN}=================================================================${RC}"
printf "%b\n" "${YELLOW}         Orca ADE — Linux Installer & Updater                    ${RC}"
printf "%b\n" "${CYAN}=================================================================${RC}"
printf "%b\n" "${GREEN}  - ADE for running Claude Code, Codex, Gemini, Cursor CLI, etc.${RC}"
printf "%b\n" "${GREEN}  - Parallel AI coding agents across isolated git worktrees      ${RC}"
printf "%b\n" "${GREEN}  - Official downloads: https://onorca.dev                       ${RC}"
printf "%b\n" "${CYAN}=================================================================${RC}"
echo ""

# ── Detect Installed Version ──────────────────────────────────────────────────
detect_installed_version() {
    if command_exists orca-ide; then
        if command_exists rpm && rpm -q orca-ide >/dev/null 2>&1; then
            rpm -q orca-ide --qf '%{VERSION}' 2>/dev/null || echo "installed"
        elif command_exists dpkg-query && dpkg-query -W -f='${Version}' orca-ide >/dev/null 2>&1; then
            dpkg-query -W -f='${Version}' orca-ide 2>/dev/null || echo "installed"
        elif command_exists pacman && (pacman -Q orca-ide-bin >/dev/null 2>&1 || pacman -Q orca-ide >/dev/null 2>&1); then
            pacman -Q orca-ide-bin 2>/dev/null | awk '{print $2}' || pacman -Q orca-ide 2>/dev/null | awk '{print $2}'
        else
            echo "installed"
        fi
    elif [ -x "/opt/Orca/orca-ide" ]; then
        if command_exists rpm && rpm -q orca-ide >/dev/null 2>&1; then
            rpm -q orca-ide --qf '%{VERSION}' 2>/dev/null || echo "installed"
        elif command_exists dpkg-query && dpkg-query -W -f='${Version}' orca-ide >/dev/null 2>&1; then
            dpkg-query -W -f='${Version}' orca-ide 2>/dev/null || echo "installed"
        else
            echo "installed"
        fi
    elif [ -x "$HOME/.local/share/orca/Orca.AppImage" ] || [ -x "$HOME/.local/bin/orca-ide" ]; then
        echo "installed (appimage)"
    else
        echo ""
    fi
}

# ── Resilient Asset Discovery ────────────────────────────────────────────────
fetch_release_assets() {
    # Tier 1: GitHub API (JSON)
    api_content=$(curl -fsSL --connect-timeout 5 --max-time 10 "$ORCA_API_URL" 2>/dev/null || true)
    if echo "$api_content" | grep -q "browser_download_url"; then
        echo "$api_content" | sed -n 's/.*"browser_download_url"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p'
        return 0
    fi

    # Tier 2: HTTP redirect tag inspection + expanded_assets (bypasses API rate limits)
    tag=$(curl -sIL --connect-timeout 5 --max-time 10 -o /dev/null -w "%{url_effective}" "$ORCA_WEB_URL" 2>/dev/null | sed -e 's#.*/tag/##' -e 's#.*/##')
    if [ -n "$tag" ] && [ "$tag" != "latest" ]; then
        expanded_assets=$(curl -fsSL --connect-timeout 5 --max-time 15 "https://github.com/stablyai/orca/releases/expanded_assets/$tag" 2>/dev/null || true)
        if [ -n "$expanded_assets" ]; then
            echo "$expanded_assets" | grep -o 'href="[^"]*"' | sed -e 's/href="//' -e 's/"//' | sed -e 's#^https://github.com##' -e 's#^#https://github.com#'
            return 0
        fi
    fi

    # Tier 3: Scrape main releases page HTML
    html_content=$(curl -fsSL --connect-timeout 5 --max-time 15 "$ORCA_WEB_URL" 2>/dev/null || true)
    if [ -n "$html_content" ]; then
        echo "$html_content" | grep -o 'href="[^"]*"' | sed -e 's/href="//' -e 's/"//' | grep "/stablyai/orca/releases/download/" | sed -e 's#^https://github.com##' -e 's#^#https://github.com#'
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
    tag="$ORCA_FALLBACK_TAG"
    ver="${tag#v}"
    case "$pattern" in
        *x86_64\.rpm) echo "https://github.com/stablyai/orca/releases/download/${tag}/orca-ide-${ver}.x86_64.rpm" ;;
        *aarch64\.rpm) echo "https://github.com/stablyai/orca/releases/download/${tag}/orca-ide-${ver}.aarch64.rpm" ;;
        *amd64\.deb) echo "https://github.com/stablyai/orca/releases/download/${tag}/orca-ide_${ver}_amd64.deb" ;;
        *arm64\.deb) echo "https://github.com/stablyai/orca/releases/download/${tag}/orca-ide_${ver}_arm64.deb" ;;
        *orca-linux\.AppImage) echo "https://github.com/stablyai/orca/releases/download/${tag}/orca-linux.AppImage" ;;
        *orca-linux-arm64\.AppImage) echo "https://github.com/stablyai/orca/releases/download/${tag}/orca-linux-arm64.AppImage" ;;
        *) return 1 ;;
    esac
}

# ── Ensure CLI & Desktop Integrations ─────────────────────────────────────────
setup_integrations() {
    mkdir -p "$HOME/.local/bin"
    mkdir -p "$HOME/.local/share/applications"
    mkdir -p "$HOME/.local/share/icons/hicolor/512x512/apps"

    # 1. User CLI symlink to orca-ide
    if [ -x "/opt/Orca/orca-ide" ]; then
        ln -sf "/opt/Orca/orca-ide" "$HOME/.local/bin/orca-ide"
        if [ -w "/usr/local/bin" ]; then
            ln -sf "/opt/Orca/orca-ide" "/usr/local/bin/orca-ide" 2>/dev/null || true
        elif [ -n "$ESCALATION_TOOL" ]; then
            "$ESCALATION_TOOL" ln -sf "/opt/Orca/orca-ide" "/usr/local/bin/orca-ide" 2>/dev/null || true
        fi
    fi

    # 2. Friendly 'orca' shortcut if not conflicting with GNOME screen reader (/usr/bin/orca)
    if ! command_exists orca; then
        if [ -x "$HOME/.local/bin/orca-ide" ]; then
            ln -sf "$HOME/.local/bin/orca-ide" "$HOME/.local/bin/orca"
        elif [ -x "/opt/Orca/orca-ide" ]; then
            ln -sf "/opt/Orca/orca-ide" "$HOME/.local/bin/orca"
        fi
    else
        existing_orca="$(command -v orca)"
        if [ "$existing_orca" != "$HOME/.local/bin/orca" ] && [ "$existing_orca" != "/usr/local/bin/orca" ]; then
            printf "%b\n" "${CYAN}[i] System screen reader found at $existing_orca; keeping 'orca' command reserved.${RC}"
            printf "%b\n" "${CYAN}    Launch Orca ADE with: orca-ide${RC}"
        fi
    fi

    # 3. Ensure icon exists in standard user paths
    user_icon="$HOME/.local/share/icons/hicolor/512x512/apps/orca-ide.png"
    if [ ! -f "$user_icon" ]; then
        if [ -f "/usr/share/icons/hicolor/512x512/apps/orca-ide.png" ]; then
            cp "/usr/share/icons/hicolor/512x512/apps/orca-ide.png" "$user_icon" 2>/dev/null || true
        elif [ -f "$ASSET_ICON" ]; then
            cp "$ASSET_ICON" "$user_icon" 2>/dev/null || true
        else
            curl -fsSL "https://www.onorca.dev/icon.png" -o "$user_icon" 2>/dev/null || true
        fi
    fi

    # 4. Polish Desktop Entry with proper Development;IDE; categories
    user_desktop="$HOME/.local/share/applications/orca-ide.desktop"
    exec_target="/opt/Orca/orca-ide"
    [ -x "$exec_target" ] || exec_target="$HOME/.local/bin/orca-ide"

    cat > "$user_desktop" <<EOF
[Desktop Entry]
Name=Orca
GenericName=Agent Development Environment
Comment=$APP_DESC
Exec=$exec_target %U
Terminal=false
Type=Application
Icon=orca-ide
StartupWMClass=orca
MimeType=text/markdown;text/csv;text/tab-separated-values;x-scheme-handler/orca;
Categories=Development;IDE;
EOF
    chmod 644 "$user_desktop"

    if command_exists update-desktop-database; then
        update-desktop-database "$HOME/.local/share/applications" >/dev/null 2>&1 || true
    fi
}

# ── AppImage Fallback Installer ───────────────────────────────────────────────
install_appimage() {
    printf "%b\n" "${YELLOW}[*] Installing Orca via portable AppImage...${RC}"
    if [ "$ARCH" = "aarch64" ]; then
        app_pattern="orca-linux-arm64\.AppImage$"
    else
        app_pattern="orca-linux\.AppImage$"
    fi

    download_url=$(get_asset_url "$app_pattern")
    if [ -z "$download_url" ]; then
        printf "%b\n" "${RED}[✗] Failed to resolve Orca AppImage download URL.${RC}"
        exit 1
    fi

    app_dir="$HOME/.local/share/orca"
    app_bin="$app_dir/Orca.AppImage"
    mkdir -p "$app_dir"
    mkdir -p "$HOME/.local/bin"

    printf "%b\n" "${YELLOW}[*] Downloading Orca AppImage...${RC}"
    printf "%b\n" "${CYAN}    URL: $download_url${RC}"
    curl -fsSL --progress-bar "$download_url" -o "$app_bin"

    chmod +x "$app_bin"
    ln -sf "$app_bin" "$HOME/.local/bin/orca-ide"

    setup_integrations
    printf "%b\n" "${GREEN}[✓] Orca AppImage installed successfully to $app_bin${RC}"
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
            printf "%b\n" "${YELLOW}[*] Installing orca-ide-bin from AUR using $AUR_HELPER...${RC}"
            if "$AUR_HELPER" -S --needed --noconfirm orca-ide-bin; then
                setup_integrations
                printf "%b\n" "${GREEN}[✓] Orca installed via AUR.${RC}"
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
        if [ "$ARCH" = "aarch64" ]; then
            rpm_pattern="orca-ide-.*\.aarch64\.rpm$"
        else
            rpm_pattern="orca-ide-.*\.x86_64\.rpm$"
        fi

        download_url=$(get_asset_url "$rpm_pattern")
        if [ -z "$download_url" ]; then
            printf "%b\n" "${YELLOW}[!] Could not resolve RPM asset. Falling back to AppImage...${RC}"
            install_appimage
        else
            tmp_rpm=$(mktemp "${TMPDIR:-/tmp}/orca-ide.XXXXXX.rpm")
            trap 'rm -f "$tmp_rpm"' 0 INT TERM
            printf "%b\n" "${YELLOW}[*] Downloading RPM: $download_url${RC}"
            curl -fsSL --progress-bar "$download_url" -o "$tmp_rpm"

            printf "%b\n" "${YELLOW}[*] Installing RPM package via $PACKAGER...${RC}"
            "$ESCALATION_TOOL" "$PACKAGER" install -y "$tmp_rpm"
            rm -f "$tmp_rpm"
            trap - 0 INT TERM

            setup_integrations
            printf "%b\n" "${GREEN}[✓] Orca ADE installed successfully via RPM!${RC}"
        fi
        ;;

    apt-get|nala)
        printf "%b\n" "${YELLOW}[*] Resolving official DEB package from GitHub releases...${RC}"
        if [ "$ARCH" = "aarch64" ]; then
            deb_pattern="orca-ide_.*_arm64\.deb$"
        else
            deb_pattern="orca-ide_.*_amd64\.deb$"
        fi

        download_url=$(get_asset_url "$deb_pattern")
        if [ -z "$download_url" ]; then
            printf "%b\n" "${YELLOW}[!] Could not resolve DEB asset. Falling back to AppImage...${RC}"
            install_appimage
        else
            tmp_deb=$(mktemp "${TMPDIR:-/tmp}/orca-ide.XXXXXX.deb")
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
            printf "%b\n" "${GREEN}[✓] Orca ADE installed successfully via DEB!${RC}"
        fi
        ;;

    zypper)
        printf "%b\n" "${YELLOW}[*] Resolving RPM package for openSUSE...${RC}"
        if [ "$ARCH" = "aarch64" ]; then
            rpm_pattern="orca-ide-.*\.aarch64\.rpm$"
        else
            rpm_pattern="orca-ide-.*\.x86_64\.rpm$"
        fi

        download_url=$(get_asset_url "$rpm_pattern")
        if [ -z "$download_url" ]; then
            install_appimage
        else
            tmp_rpm=$(mktemp "${TMPDIR:-/tmp}/orca-ide.XXXXXX.rpm")
            trap 'rm -f "$tmp_rpm"' 0 INT TERM
            printf "%b\n" "${YELLOW}[*] Downloading RPM: $download_url${RC}"
            curl -fsSL --progress-bar "$download_url" -o "$tmp_rpm"

            printf "%b\n" "${YELLOW}[*] Installing RPM via zypper...${RC}"
            "$ESCALATION_TOOL" zypper --non-interactive install --allow-unsigned-rpm "$tmp_rpm"
            rm -f "$tmp_rpm"
            trap - 0 INT TERM

            setup_integrations
            printf "%b\n" "${GREEN}[✓] Orca ADE installed successfully via zypper!${RC}"
        fi
        ;;

    *)
        printf "%b\n" "${YELLOW}[*] Unsupported direct package manager ($PACKAGER). Using AppImage installer...${RC}"
        install_appimage
        ;;
esac

echo ""
printf "%b\n" "${GREEN}=================================================================${RC}"
printf "%b\n" "${GREEN}  ✅  Orca ADE setup complete!                                   ${RC}"
printf "%b\n" "${CYAN}=================================================================${RC}"
printf "%b\n" "${YELLOW}  Launch options:${RC}"
printf "%b\n" "${CYAN}    Desktop   → App Menu / Search 'Orca'                         ${RC}"
printf "%b\n" "${CYAN}    Terminal  → 'orca-ide' or 'orca'                             ${RC}"
printf "%b\n" "${CYAN}=================================================================${RC}"
echo ""
