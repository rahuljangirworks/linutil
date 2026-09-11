#!/bin/sh -e

# Description: Install RustDesk remote desktop and configure it to run
#              silently in the background after login.
# Rerunnable: Yes - skips completed steps, supports --update / --force

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [ -f "$SCRIPT_DIR/../../common-script.sh" ]; then
    . "$SCRIPT_DIR/../../common-script.sh"
elif [ -f "../../common-script.sh" ]; then
    . ../../common-script.sh
else
    printf "%b\n" "\033[31mError: common-script.sh not found\033[0m" >&2
    exit 1
fi

# ── Configuration & CLI flags ────────────────────────────────────────────────

RUSTDESK_API_URL="https://api.github.com/repos/rustdesk/rustdesk/releases/latest"
RUSTDESK_WEB_URL="https://github.com/rustdesk/rustdesk/releases/latest"
RUSTDESK_FALLBACK_VERSION="1.4.9"
RUSTDESK_INSTALL_KIND=""
RUSTDESK_LAUNCH_CMD="rustdesk"
RUSTDESK_TRAY_CMD="rustdesk --tray"
RUSTDESK_SESSION_TYPE="${XDG_SESSION_TYPE:-unknown}"
RUSTDESK_DISPLAY_MANAGER="unknown"
RUSTDESK_XPROFILE_STATUS="not checked"
RUSTDESK_XDG_STATUS="not checked"
FORCE_UPDATE=0

for arg in "$@"; do
    case "$arg" in
        --force|-f|--update|-u)
            FORCE_UPDATE=1
            ;;
    esac
done

# ── Detect Installation ──────────────────────────────────────────────────────

detectRustDeskInstall() {
    if command -v rustdesk > /dev/null 2>&1; then
        RUSTDESK_INSTALL_KIND="native"
        RUSTDESK_LAUNCH_CMD="rustdesk"
        RUSTDESK_TRAY_CMD="rustdesk --tray"
        return 0
    fi

    if command -v flatpak > /dev/null 2>&1 && flatpak info com.rustdesk.RustDesk > /dev/null 2>&1; then
        RUSTDESK_INSTALL_KIND="flatpak"
        RUSTDESK_LAUNCH_CMD="flatpak run com.rustdesk.RustDesk"
        RUSTDESK_TRAY_CMD="flatpak run com.rustdesk.RustDesk --tray"
        return 0
    fi

    return 1
}

# ── Resilient Asset Discovery ────────────────────────────────────────────────
# 1. Tries GitHub REST API
# 2. Falls back to scraping release expanded assets via redirect tag (immune to API rate limits)
# 3. Falls back to scraping release HTML
# 4. Falls back to verified known stable release URL

fetchReleaseAssets() {
    # Tier 1: GitHub API (JSON)
    local api_content
    api_content=$(curl -fsSL --connect-timeout 5 --max-time 10 "$RUSTDESK_API_URL" 2>/dev/null || true)
    if echo "$api_content" | grep -q "browser_download_url"; then
        echo "$api_content" | sed -n 's/.*"browser_download_url"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p'
        return 0
    fi

    # Tier 2: Discover tag via HTTP redirect and scrape expanded assets (bypasses API rate limits)
    local tag
    tag=$(curl -sIL --connect-timeout 5 --max-time 10 -o /dev/null -w "%{url_effective}" "$RUSTDESK_WEB_URL" 2>/dev/null | sed -e 's#.*/tag/##' -e 's#.*/##')
    if [ -n "$tag" ] && [ "$tag" != "latest" ]; then
        local expanded_assets
        expanded_assets=$(curl -fsSL --connect-timeout 5 --max-time 15 "https://github.com/rustdesk/rustdesk/releases/expanded_assets/$tag" 2>/dev/null || true)
        if [ -n "$expanded_assets" ]; then
            echo "$expanded_assets" | grep -o 'href="[^"]*"' | sed -e 's/href="//' -e 's/"//' | sed -e 's#^https://github.com##' -e 's#^#https://github.com#'
            return 0
        fi
    fi

    # Tier 3: Scrape main releases page HTML
    local html_content
    html_content=$(curl -fsSL --connect-timeout 5 --max-time 15 "$RUSTDESK_WEB_URL" 2>/dev/null || true)
    if [ -n "$html_content" ]; then
        echo "$html_content" | grep -o 'href="[^"]*"' | sed -e 's/href="//' -e 's/"//' | grep "/rustdesk/rustdesk/releases/download/" | sed -e 's#^https://github.com##' -e 's#^#https://github.com#'
        return 0
    fi

    return 1
}

releaseAssetUrl() {
    local include_pattern="$1"
    local exclude_pattern="${2:-__rustdesk_never_match__}"

    fetchReleaseAssets 2>/dev/null |
        grep -E "$include_pattern" |
        grep -Ev "$exclude_pattern" |
        head -n 1
}

# ── Download and Install Native Package ──────────────────────────────────────

downloadAndInstall() {
    local url="$1"
    local suffix="$2"
    local temp_pkg

    if [ -z "$url" ]; then
        return 1
    fi

    temp_pkg=$(mktemp "${TMPDIR:-/tmp}/rustdesk.XXXXXX.$suffix")
    printf "%b\n" "${YELLOW}Downloading RustDesk package from:${RC}"
    printf "%b\n" "${CYAN}$url${RC}"

    if ! curl -fL --progress-bar "$url" -o "$temp_pkg"; then
        printf "%b\n" "${RED}Download failed for $url${RC}"
        rm -f "$temp_pkg"
        return 1
    fi

    printf "%b\n" "${YELLOW}Installing native package...${RC}"
    case "$suffix" in
        deb)
            "$ESCALATION_TOOL" apt-get update -qq || true
            if ! "$ESCALATION_TOOL" apt-get install -y "$temp_pkg"; then
                printf "%b\n" "${YELLOW}Resolving missing dependencies with apt-get -f install...${RC}"
                "$ESCALATION_TOOL" dpkg -i "$temp_pkg" || true
                "$ESCALATION_TOOL" apt-get install -f -y || {
                    rm -f "$temp_pkg"
                    return 1
                }
            fi
            ;;
        rpm)
            if ! "$ESCALATION_TOOL" "$PACKAGER" install -y "$temp_pkg"; then
                printf "%b\n" "${RED}RPM installation failed.${RC}"
                rm -f "$temp_pkg"
                return 1
            fi
            ;;
        pkg.tar.zst)
            if ! "$ESCALATION_TOOL" pacman -U --needed --noconfirm "$temp_pkg"; then
                printf "%b\n" "${RED}Arch package installation failed.${RC}"
                rm -f "$temp_pkg"
                return 1
            fi
            ;;
        *)
            rm -f "$temp_pkg"
            return 1
            ;;
    esac

    rm -f "$temp_pkg"
    return 0
}

# ── Install RustDesk ─────────────────────────────────────────────────────────

installRustDesk() {
    if [ "$FORCE_UPDATE" -eq 0 ] && detectRustDeskInstall; then
        printf "%b\n" "${GREEN}✓ RustDesk already installed (${RUSTDESK_INSTALL_KIND})${RC}"
        printf "%b\n" "${CYAN}  (Pass --update or --force to reinstall or update)${RC}"
        return 0
    fi

    printf "%b\n" "${YELLOW}Installing RustDesk...${RC}"

    case "$PACKAGER" in
        pacman)
            # Tier A: Prefer AUR helper if available (resolves all dependencies cleanly)
            if [ -n "$AUR_HELPER" ] && command_exists "$AUR_HELPER"; then
                printf "%b\n" "${CYAN}Installing rustdesk-bin via AUR helper ($AUR_HELPER)...${RC}"
                if "$AUR_HELPER" -S --needed --noconfirm rustdesk-bin; then
                    printf "%b\n" "${GREEN}✓ RustDesk installed via AUR ($AUR_HELPER)${RC}"
                    return 0
                fi
                printf "%b\n" "${YELLOW}AUR install failed, falling back to upstream Arch package...${RC}"
            fi

            # Tier B: Upstream Arch package from GitHub releases
            LATEST_URL=$(releaseAssetUrl "rustdesk-.*-${ARCH}\\.pkg\\.tar\\.zst$")
            if [ -z "$LATEST_URL" ]; then
                LATEST_URL="https://github.com/rustdesk/rustdesk/releases/download/${RUSTDESK_FALLBACK_VERSION}/rustdesk-${RUSTDESK_FALLBACK_VERSION}-0-${ARCH}.pkg.tar.zst"
            fi

            if downloadAndInstall "$LATEST_URL" "pkg.tar.zst"; then
                printf "%b\n" "${GREEN}✓ RustDesk installed from upstream Arch package${RC}"
            else
                printf "%b\n" "${YELLOW}Could not install native Arch package, trying Flatpak...${RC}"
                installFlatpak
            fi
            ;;
        apt-get|nala)
            LATEST_URL=$(releaseAssetUrl "rustdesk-.*-${ARCH}\\.deb$" "sciter")
            if [ -z "$LATEST_URL" ]; then
                LATEST_URL="https://github.com/rustdesk/rustdesk/releases/download/${RUSTDESK_FALLBACK_VERSION}/rustdesk-${RUSTDESK_FALLBACK_VERSION}-${ARCH}.deb"
            fi

            if downloadAndInstall "$LATEST_URL" "deb"; then
                printf "%b\n" "${GREEN}✓ RustDesk installed from official Debian package${RC}"
            else
                printf "%b\n" "${YELLOW}Could not install native Debian package, trying Flatpak...${RC}"
                installFlatpak
            fi
            ;;
        dnf|yum)
            printf "%b\n" "${CYAN}Official RustDesk method for Fedora/RHEL: native RPM package.${RC}"
            LATEST_URL=$(releaseAssetUrl "rustdesk-.*\\.${ARCH}\\.rpm$" "suse")
            if [ -z "$LATEST_URL" ]; then
                LATEST_URL="https://github.com/rustdesk/rustdesk/releases/download/${RUSTDESK_FALLBACK_VERSION}/rustdesk-${RUSTDESK_FALLBACK_VERSION}-0.${ARCH}.rpm"
            fi

            if downloadAndInstall "$LATEST_URL" "rpm"; then
                printf "%b\n" "${GREEN}✓ RustDesk installed from official RPM package${RC}"
            else
                printf "%b\n" "${YELLOW}Could not install official RPM package, trying Flatpak...${RC}"
                installFlatpak
            fi
            ;;
        zypper)
            LATEST_URL=$(releaseAssetUrl "rustdesk-.*\\.${ARCH}-suse\\.rpm$")
            if [ -z "$LATEST_URL" ]; then
                LATEST_URL="https://github.com/rustdesk/rustdesk/releases/download/${RUSTDESK_FALLBACK_VERSION}/rustdesk-${RUSTDESK_FALLBACK_VERSION}-0.${ARCH}-suse.rpm"
            fi

            if downloadAndInstall "$LATEST_URL" "rpm"; then
                printf "%b\n" "${GREEN}✓ RustDesk installed from upstream openSUSE package${RC}"
            else
                printf "%b\n" "${YELLOW}Could not install native openSUSE package, trying Flatpak...${RC}"
                installFlatpak
            fi
            ;;
        *)
            printf "%b\n" "${YELLOW}No native RustDesk package path for $PACKAGER, trying Flatpak...${RC}"
            installFlatpak
            ;;
    esac

    if detectRustDeskInstall; then
        return 0
    fi

    printf "%b\n" "${RED}✗ RustDesk install finished, but no runnable RustDesk command was found.${RC}"
    exit 1
}

installFlatpak() {
    checkFlatpak
    flatpak install -y flathub com.rustdesk.RustDesk
    RUSTDESK_INSTALL_KIND="flatpak"
    RUSTDESK_LAUNCH_CMD="flatpak run com.rustdesk.RustDesk"
    RUSTDESK_TRAY_CMD="flatpak run com.rustdesk.RustDesk --tray"
    printf "%b\n" "${GREEN}✓ RustDesk installed via Flatpak${RC}"
}

# ── Enable System Service (Boot Persistence) ─────────────────────────────────
# The rustdesk.service daemon runs independently of any GUI session.
# This keeps RustDesk accepting remote connections across reboots.

enableService() {
    if [ "$RUSTDESK_INSTALL_KIND" = "flatpak" ]; then
        printf "%b\n" "${YELLOW}→ Flatpak install detected; no system rustdesk.service is available.${RC}"
        return 0
    fi

    if ! command -v systemctl > /dev/null 2>&1; then
        printf "%b\n" "${YELLOW}→ systemctl not found; skipping RustDesk system service.${RC}"
        return 0
    fi

    # Reload systemd units so newly unpacked package units are immediately visible
    "$ESCALATION_TOOL" systemctl daemon-reload > /dev/null 2>&1 || true

    if ! systemctl list-unit-files rustdesk.service > /dev/null 2>&1 && [ ! -f /usr/lib/systemd/system/rustdesk.service ]; then
        printf "%b\n" "${YELLOW}→ No rustdesk.service found; RustDesk will start after user login only.${RC}"
        return 0
    fi

    printf "%b\n" "${YELLOW}Configuring RustDesk system service for boot persistence...${RC}"
    "$ESCALATION_TOOL" systemctl enable --now rustdesk.service 2>/dev/null || \
        "$ESCALATION_TOOL" systemctl enable --now rustdesk 2>/dev/null || true

    if systemctl is-active --quiet rustdesk 2>/dev/null; then
        printf "%b\n" "${GREEN}✓ RustDesk system service is active and running${RC}"
    else
        printf "%b\n" "${YELLOW}⚠️  RustDesk service enabled for boot (start with: sudo systemctl start rustdesk)${RC}"
    fi
}

# ── Auto-Start Silently After Login ──────────────────────────────────────────
# Strategy:
#   ~/.config/autostart/rustdesk-tray.desktop — Universal XDG autostart,
#                  executed by GNOME, KDE, XFCE, and DWM (via dex).
#   ~/.xprofile  — Fallback/direct hook for X11 / LightDM / startx sessions.
#                  Idempotent check prevents duplicate tray icons.

detectLoginSession() {
    RUSTDESK_SESSION_TYPE="${XDG_SESSION_TYPE:-unknown}"
    RUSTDESK_DISPLAY_MANAGER="unknown"

    if [ -L /etc/systemd/system/display-manager.service ]; then
        RUSTDESK_DISPLAY_MANAGER=$(basename "$(readlink /etc/systemd/system/display-manager.service)" .service)
    elif command -v pgrep > /dev/null 2>&1; then
        if pgrep -x lightdm > /dev/null 2>&1; then
            RUSTDESK_DISPLAY_MANAGER="lightdm"
        elif pgrep -x gdm > /dev/null 2>&1 || pgrep -x gdm3 > /dev/null 2>&1; then
            RUSTDESK_DISPLAY_MANAGER="gdm"
        elif pgrep -x sddm > /dev/null 2>&1; then
            RUSTDESK_DISPLAY_MANAGER="sddm"
        fi
    fi

    printf "%b\n" "${CYAN}Detected session: ${RUSTDESK_SESSION_TYPE}, display manager: ${RUSTDESK_DISPLAY_MANAGER}${RC}"
}

shouldUseXprofile() {
    if [ "$RUSTDESK_SESSION_TYPE" = "x11" ]; then
        return 0
    fi

    if [ "$RUSTDESK_DISPLAY_MANAGER" = "lightdm" ]; then
        return 0
    fi

    if [ -f "$HOME/.xinitrc" ] || [ -f "$HOME/.xprofile" ]; then
        return 0
    fi

    if [ "${XDG_CURRENT_DESKTOP}" = "dwm" ] || [ "${DESKTOP_SESSION}" = "dwm" ]; then
        return 0
    fi

    if command -v pgrep > /dev/null 2>&1 && pgrep -x Xorg > /dev/null 2>&1; then
        return 0
    fi

    return 1
}

writeXprofileAutostart() {
    XPROFILE="$HOME/.xprofile"
    XPROFILE_MARKER="# rustdesk autostart"
    XPROFILE_TMP=""

    if [ -f "$XPROFILE" ] && grep -q "$XPROFILE_MARKER" "$XPROFILE" 2>/dev/null; then
        XPROFILE_TMP=$(mktemp)
        awk -v marker="$XPROFILE_MARKER" '
            $0 == marker { skip = 1; next }
            skip && /^# rustdesk autostart/ { next }
            skip && /rustdesk/ { next }
            skip && /^$/ { skip = 0; next }
            { print }
        ' "$XPROFILE" > "$XPROFILE_TMP"
        mv "$XPROFILE_TMP" "$XPROFILE"
    fi

    cat >> "$XPROFILE" << 'EOF'

# rustdesk autostart
if command -v rustdesk >/dev/null 2>&1 && ! pgrep -u "$(id -u)" -x rustdesk >/dev/null 2>&1; then
    rustdesk --tray >/dev/null 2>&1 &
fi
EOF
    chmod +x "$XPROFILE"
    RUSTDESK_XPROFILE_STATUS="enabled (~/.xprofile)"
    printf "%b\n" "${GREEN}✓ Configured idempotent RustDesk autostart in ~/.xprofile${RC}"
}

writeXdgAutostart() {
    AUTOSTART_DIR="$HOME/.config/autostart"
    DESKTOP_FILE="$AUTOSTART_DIR/rustdesk-tray.desktop"

    mkdir -p "$AUTOSTART_DIR"

    cat > "$DESKTOP_FILE" << EOF
[Desktop Entry]
Type=Application
Name=RustDesk
Comment=RustDesk remote desktop (tray, no window)
Exec=$RUSTDESK_TRAY_CMD
Icon=rustdesk
Terminal=false
Hidden=false
NoDisplay=false
X-GNOME-Autostart-enabled=true
EOF
    RUSTDESK_XDG_STATUS="enabled (~/.config/autostart/rustdesk-tray.desktop)"
    printf "%b\n" "${GREEN}✓ Wrote ~/.config/autostart/rustdesk-tray.desktop (XDG autostart / dex)${RC}"
}

setupAutostart() {
    printf "%b\n" "${YELLOW}Configuring RustDesk to auto-start silently after login...${RC}"
    detectLoginSession

    # 1. Universal XDG autostart entry (runs on GNOME, KDE, XFCE, and DWM via dex)
    writeXdgAutostart

    # 2. Configure ~/.xprofile for X11 / DWM / LightDM / startx sessions
    if shouldUseXprofile; then
        writeXprofileAutostart
    else
        RUSTDESK_XPROFILE_STATUS="skipped (Wayland / pure systemd session)"
    fi

    if [ "${XDG_CURRENT_DESKTOP}" = "dwm" ] || [ "${DESKTOP_SESSION}" = "dwm" ]; then
        printf "%b\n" "${CYAN}→ DWM session active: RustDesk will launch on login via XDG autostart (dex) and ~/.xprofile${RC}"
    fi
}

# ── Themed Tray Icon for DWM / Quickshell ────────────────────────────────────

setupRustDeskTrayIcon() {
    printf "%b\n" "${YELLOW}Configuring themed RustDesk tray icon for DWM / Quickshell...${RC}"

    ASSET_DIRS="$HOME/.config/quickshell/assets $HOME/.local/share/dwm-jangir/config/quickshell/assets"
    REPO_DIR="$HOME/work/personal-projacts/dwm-jangir"
    if [ -d "$REPO_DIR/config/quickshell/assets" ]; then
        ASSET_DIRS="$ASSET_DIRS $REPO_DIR/config/quickshell/assets"
    fi

    for d in $ASSET_DIRS; do
        mkdir -p "$d"
        cat > "$d/rustdesk-tray.svg" << 'EOF'
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24">
  <title>RustDesk</title>
  <g transform="translate(12, 12) scale(0.62) translate(-30.9845, -904.7482)" fill="#ECEFF4">
    <path d="m 40.309479,897.8163 -2.13532,2.12189 c -0.37566,0.3367 -0.557321,0.87878 -0.34675,1.33694 1.422559,2.97602 0.882559,6.52382 -1.45146,8.85602 -2.33502,2.33131 -5.88696,2.8707 -8.866524,1.44881 -0.43892,-0.1965 -0.953964,-0.03 -1.292057,0.31269 l -2.169919,2.16641 c -0.255052,0.2498 -0.3806,0.6023 -0.34007,0.95579 0.04054,0.3545 0.243189,0.6695 0.54767,0.8541 5.1129,3.09451 11.678999,2.30561 15.911089,-1.9116 4.232081,-4.2162 5.03876,-10.77258 1.9554,-15.88729 -0.17696,-0.31103 -0.48935,-0.52234 -0.84425,-0.5717 -0.35489,-0.0503 -0.71276,0.0681 -0.967809,0.31794 z M 21.84293,895.5107 c -4.252844,4.20042 -5.086212,10.75775 -2.019657,15.88535 0.176955,0.312 0.488356,0.5233 0.843254,0.5727 0.354897,0.05 0.712761,-0.0679 0.968802,-0.319 l 2.123457,-2.1091 c 0.384554,-0.3367 0.572151,-0.8847 0.358619,-1.3488 -1.422557,-2.976 -0.883552,-6.52373 1.451458,-8.85593 2.334022,-2.33127 5.886947,-2.87085 8.865525,-1.44997 0.433981,0.19451 0.94211,0.033 1.281191,-0.29971 l 2.181779,-2.1792 c 0.255051,-0.24884 0.380601,-0.60134 0.340071,-0.95581 -0.04149,-0.35349 -0.24319,-0.66847 -0.54767,-0.85411 -5.121801,-3.06787 -11.678015,-2.25523 -15.893292,1.97185 z"/>
  </g>
</svg>
EOF
    done

    printf "%b\n" "${GREEN}✓ Installed minimal Nord rustdesk-tray.svg${RC}"

    # Reload Quickshell if running so the icon updates immediately
    if command -v dwm-quickshell-controlcenter >/dev/null 2>&1 && pgrep -u "$(id -u)" -x quickshell >/dev/null 2>&1; then
        dwm-quickshell-controlcenter action restart-quickshell >/dev/null 2>&1 || true
    fi
}

# ── Status ───────────────────────────────────────────────────────────────────

printStatus() {
    printf "%b\n" "${GREEN}========================================${RC}"
    printf "%b\n" "${GREEN}  RustDesk Setup Complete!${RC}"
    printf "%b\n" "${GREEN}========================================${RC}"

    if command -v rustdesk > /dev/null 2>&1; then
        RUSTDESK_ID=$(rustdesk --get-id 2>/dev/null || echo "(run 'rustdesk' once to initialize ID)")
        printf "%b\n" "${CYAN}  Your RustDesk ID : $RUSTDESK_ID${RC}"
    fi

    printf "%b\n" "${CYAN}  Install type     : ${RUSTDESK_INSTALL_KIND:-unknown}${RC}"
    printf "%b\n" "${CYAN}  Session          : ${RUSTDESK_SESSION_TYPE} / ${RUSTDESK_DISPLAY_MANAGER}${RC}"
    printf "%b\n" "${CYAN}  XDG autostart    : ${RUSTDESK_XDG_STATUS}${RC}"
    printf "%b\n" "${CYAN}  ~/.xprofile      : ${RUSTDESK_XPROFILE_STATUS}${RC}"
    printf "%b\n" "${CYAN}  Tray Icon        : minimal Nord SVG (~/.config/quickshell/assets/rustdesk-tray.svg)${RC}"
    if [ "$RUSTDESK_INSTALL_KIND" = "native" ]; then
        if systemctl is-active --quiet rustdesk 2>/dev/null; then
            printf "%b\n" "${CYAN}  Boot service     : active (rustdesk.service running)${RC}"
        else
            printf "%b\n" "${CYAN}  Boot service     : enabled (rustdesk.service)${RC}"
        fi
    else
        printf "%b\n" "${CYAN}  Boot service     : unavailable for Flatpak install${RC}"
    fi
    printf "%b\n" "${CYAN}  Open GUI         : $RUSTDESK_LAUNCH_CMD${RC}"
    printf "%b\n" "${CYAN}  Start Tray       : $RUSTDESK_TRAY_CMD${RC}"
    printf "%b\n" "${GREEN}========================================${RC}"
    printf "%b\n" "${YELLOW}Tip: Set permanent password: sudo rustdesk --password <your_password>${RC}"
    printf "%b\n" "${YELLOW}Tip: Re-run with --update to fetch the latest upstream version anytime.${RC}"
}

# ── Main ─────────────────────────────────────────────────────────────────────

checkEnv
checkEscalationTool
installRustDesk
enableService
setupAutostart
setupRustDeskTrayIcon
printStatus
