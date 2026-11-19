#!/bin/sh -e

# Description: Install and configure Tailscale VPN using the official Linux installer.
#              Prompts before service changes, SSH mode changes, operator access, and tray setup.
# Repository: https://tailscale.com
# Rerunnable: Yes - keeps existing enrollment and asks before optional configuration changes.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [ -f "$SCRIPT_DIR/../../common-script.sh" ]; then
    . "$SCRIPT_DIR/../../common-script.sh"
elif [ -f "../../common-script.sh" ]; then
    . ../../common-script.sh
else
    printf "%b\n" "\033[31mError: common-script.sh not found\033[0m" >&2
    exit 1
fi

AUTH_TOKEN=""
TAILSCALE_HOSTNAME=""
READ_SECRET_VALUE=""
FORCE_UPDATE=0
TRAY_ONLY=0
DISABLE_TAILSCALE_SSH=no
SET_TAILSCALE_OPERATOR=no
CONFIGURE_TRAY=no
PREVIOUSLY_CONNECTED=no

for arg in "$@"; do
    case "$arg" in
        --force|-f|--update|-u)
            FORCE_UPDATE=1
            ;;
        --tray-only|--tray)
            TRAY_ONLY=1
            ;;
    esac
done

# ── Installation Methods ─────────────────────────────────────────────────────

installTailscaleWithOfficialScript() {
    printf "%b\n" "${YELLOW}Installing Tailscale with official installer...${RC}"

    if [ "$(id -u)" = "0" ]; then
        curl -fsSL https://tailscale.com/install.sh | sh
    else
        curl -fsSL https://tailscale.com/install.sh | "$ESCALATION_TOOL" sh
    fi
}

installTailscaleWithPackageManager() {
    printf "%b\n" "${YELLOW}Official script skipped or failed, installing via package manager...${RC}"

    case "$PACKAGER" in
        pacman)
            "$ESCALATION_TOOL" "$PACKAGER" -S --needed --noconfirm tailscale
            ;;
        apt-get|nala)
            "$ESCALATION_TOOL" "$PACKAGER" update -qq || true
            "$ESCALATION_TOOL" "$PACKAGER" install -y tailscale
            ;;
        dnf|yum)
            "$ESCALATION_TOOL" "$PACKAGER" install -y tailscale xsel 2>/dev/null || \
            "$ESCALATION_TOOL" "$PACKAGER" install -y tailscale
            ;;
        zypper)
            "$ESCALATION_TOOL" "$PACKAGER" install -y tailscale
            ;;
        apk)
            "$ESCALATION_TOOL" "$PACKAGER" add tailscale
            ;;
        xbps-install)
            "$ESCALATION_TOOL" "$PACKAGER" -Sy tailscale
            ;;
        eopkg)
            "$ESCALATION_TOOL" "$PACKAGER" install -y tailscale
            ;;
        *)
            printf "%b\n" "${RED}✗ Unsupported package manager: $PACKAGER${RC}"
            return 1
            ;;
    esac
}

installTailscale() {
    if [ "$TRAY_ONLY" -eq 1 ]; then
        return 0
    fi

    if [ "$FORCE_UPDATE" -eq 0 ] && command_exists tailscale; then
        CURRENT_VER=$(tailscale version 2>/dev/null | head -n 1 || echo "installed")
        printf "%b\n" "${GREEN}✓ Tailscale already installed ($CURRENT_VER)${RC}"
        printf "%b\n" "${CYAN}  (Pass --update or --force to reinstall/update)${RC}"
        return 0
    fi

    installTailscaleWithOfficialScript || installTailscaleWithPackageManager

    if command_exists tailscale; then
        CURRENT_VER=$(tailscale version 2>/dev/null | head -n 1 || echo "installed")
        printf "%b\n" "${GREEN}✓ Tailscale installed successfully ($CURRENT_VER)${RC}"
    else
        printf "%b\n" "${RED}✗ Tailscale installation failed${RC}"
        exit 1
    fi
}

# ── Enable System Service & Set Desktop Operator ─────────────────────────────

enableTailscale() {
    if command_exists systemctl; then
        "$ESCALATION_TOOL" systemctl daemon-reload >/dev/null 2>&1 || true

        if ! systemctl is-active --quiet tailscaled 2>/dev/null; then
            printf "%b\n" "${YELLOW}Enabling and starting tailscaled system service...${RC}"
            "$ESCALATION_TOOL" systemctl enable --now tailscaled
        fi

        if systemctl is-active --quiet tailscaled 2>/dev/null; then
            printf "%b\n" "${GREEN}✓ tailscaled system service is active and running${RC}"
        else
            printf "%b\n" "${YELLOW}⚠️  tailscaled enabled, but not active${RC}"
        fi
    elif command_exists rc-service; then
        printf "%b\n" "${YELLOW}Starting tailscaled with OpenRC...${RC}"
        "$ESCALATION_TOOL" rc-update add tailscale default 2>/dev/null || true
        "$ESCALATION_TOOL" rc-service tailscale start
        printf "%b\n" "${GREEN}✓ Tailscale service started${RC}"
    elif command_exists service; then
        printf "%b\n" "${YELLOW}Starting tailscaled with service...${RC}"
        "$ESCALATION_TOOL" service tailscaled start 2>/dev/null || "$ESCALATION_TOOL" service tailscale start
        printf "%b\n" "${GREEN}✓ Tailscale service started${RC}"
    else
        printf "%b\n" "${YELLOW}→ Could not detect service manager. Try manually: sudo tailscaled${RC}"
    fi

    # Only change the operator when the user explicitly selected it in preflight.
    DESKTOP_USER="${SUDO_USER:-$USER}"
    if [ "$SET_TAILSCALE_OPERATOR" = yes ] && [ -n "$DESKTOP_USER" ] && [ "$DESKTOP_USER" != "root" ]; then
        printf "%b\n" "${YELLOW}Setting Tailscale operator to '$DESKTOP_USER'...${RC}"
        "$ESCALATION_TOOL" tailscale set --operator="$DESKTOP_USER" >/dev/null 2>&1 || true
        printf "%b\n" "${GREEN}✓ Tailscale operator set to '$DESKTOP_USER' (manage via tray without sudo)${RC}"
    fi
}

# ── System Tray & DWM Autostart Configuration ────────────────────────────────

setupTailscaleSystray() {
    printf "%b\n" "${YELLOW}Configuring Tailscale System Tray for DWM / Quickshell...${RC}"

    # 1. Install local tailscale-tray script if present in repo
    REPO_TRAY_SCRIPT="$HOME/work/opensource-projacts/dwm-jangir/scripts/tailscale-tray"
    if [ -f "$REPO_TRAY_SCRIPT" ]; then
        mkdir -p "$HOME/.local/bin"
        cp -f "$REPO_TRAY_SCRIPT" "$HOME/.local/bin/tailscale-tray"
        chmod +x "$HOME/.local/bin/tailscale-tray"
        printf "%b\n" "${GREEN}✓ Installed native tailscale-tray into ~/.local/bin${RC}"
    fi

    # 1b. Install minimal themed Tailscale SVGs (Connected & Disconnected)
    ASSET_DIRS="$HOME/.config/quickshell/assets $HOME/.local/share/dwm-jangir/config/quickshell/assets"
    REPO_DIR="$HOME/work/opensource-projacts/dwm-jangir"
    if [ -d "$REPO_DIR/config/quickshell/assets" ]; then
        ASSET_DIRS="$ASSET_DIRS $REPO_DIR/config/quickshell/assets"
    fi

    for d in $ASSET_DIRS; do
        mkdir -p "$d"
        cat > "$d/tailscale-connected.svg" << 'EOF'
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24">
  <title>Tailscale Connected</title>
  <g fill="#ECEFF4">
    <circle cx="12" cy="7.6" r="1.6"/>
    <circle cx="7.6" cy="12" r="1.6"/>
    <circle cx="12" cy="12" r="1.6"/>
    <circle cx="16.4" cy="12" r="1.6"/>
    <circle cx="12" cy="16.4" r="1.6"/>
    <circle cx="7.6" cy="7.6" r="1.2" opacity="0.32"/>
    <circle cx="16.4" cy="7.6" r="1.2" opacity="0.32"/>
    <circle cx="7.6" cy="16.4" r="1.2" opacity="0.32"/>
    <circle cx="16.4" cy="16.4" r="1.2" opacity="0.32"/>
  </g>
</svg>
EOF
        cat > "$d/tailscale-disconnected.svg" << 'EOF'
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24">
  <title>Tailscale Disconnected</title>
  <g fill="#D8DEE9" opacity="0.38">
    <circle cx="12" cy="7.6" r="1.6"/>
    <circle cx="7.6" cy="12" r="1.6"/>
    <circle cx="12" cy="12" r="1.6"/>
    <circle cx="16.4" cy="12" r="1.6"/>
    <circle cx="12" cy="16.4" r="1.6"/>
    <circle cx="7.6" cy="7.6" r="1.2" opacity="0.4"/>
    <circle cx="16.4" cy="7.6" r="1.2" opacity="0.4"/>
    <circle cx="7.6" cy="16.4" r="1.2" opacity="0.4"/>
    <circle cx="16.4" cy="16.4" r="1.2" opacity="0.4"/>
  </g>
</svg>
EOF
    done
    printf "%b\n" "${GREEN}✓ Installed minimal Nord tailscale-connected.svg and tailscale-disconnected.svg${RC}"

    TRAY_CMD="tailscale-tray"
    if ! command_exists tailscale-tray; then
        TRAY_CMD="tailscale systray"
    fi

    # 2. Ensure universal XDG autostart desktop entry exists
    AUTOSTART_DIR="$HOME/.config/autostart"
    DESKTOP_FILE="$AUTOSTART_DIR/tailscale-systray.desktop"
    mkdir -p "$AUTOSTART_DIR"

    cat > "$DESKTOP_FILE" << EOF
[Desktop Entry]
Type=Application
Name=Tailscale
Comment=Tailscale Client System Tray
Exec=$TRAY_CMD
Icon=tailscale
Terminal=false
Hidden=false
NoDisplay=false
X-GNOME-Autostart-enabled=true
EOF
    printf "%b\n" "${GREEN}✓ Configured ~/.config/autostart/tailscale-systray.desktop ($TRAY_CMD)${RC}"

    # 3. Configure ~/.xprofile fallback with idempotent guard
    XPROFILE="$HOME/.xprofile"
    XPROFILE_MARKER="# tailscale autostart"
    if [ -f "$XPROFILE" ] && grep -q "$XPROFILE_MARKER" "$XPROFILE" 2>/dev/null; then
        XPROFILE_TMP=$(mktemp)
        awk -v marker="$XPROFILE_MARKER" '
            $0 == marker { skip = 1; next }
            skip && /^# tailscale autostart/ { next }
            skip && /tailscale/ { next }
            skip && /^$/ { skip = 0; next }
            { print }
        ' "$XPROFILE" > "$XPROFILE_TMP"
        mv "$XPROFILE_TMP" "$XPROFILE"
    fi

    cat >> "$XPROFILE" << 'EOF'

# tailscale autostart
if command -v tailscale-tray >/dev/null 2>&1; then
    if ! pgrep -u "$(id -u)" -f "tailscale-tray" >/dev/null 2>&1; then
        tailscale-tray >/dev/null 2>&1 &
    fi
elif command -v tailscale >/dev/null 2>&1 && ! pgrep -u "$(id -u)" -f "tailscale systray" >/dev/null 2>&1; then
    tailscale systray >/dev/null 2>&1 &
fi
EOF
    chmod +x "$XPROFILE"
    printf "%b\n" "${GREEN}✓ Configured idempotent Tailscale autostart in ~/.xprofile${RC}"

    # 4. Launch immediately if in an active graphical session (DWM / Quickshell)
    if [ -n "${DISPLAY:-}" ] || [ -n "${WAYLAND_DISPLAY:-}" ]; then
        # Stop old tailscale systray if switching to tailscale-tray
        if [ "$TRAY_CMD" = "tailscale-tray" ] && pgrep -u "$(id -u)" -f "tailscale systray" >/dev/null 2>&1; then
            pkill -u "$(id -u)" -f "tailscale systray" >/dev/null 2>&1 || true
            sleep 1
        fi

        if ! pgrep -u "$(id -u)" -f "$TRAY_CMD" >/dev/null 2>&1; then
            printf "%b\n" "${CYAN}Launching $TRAY_CMD in active desktop panel...${RC}"
            $TRAY_CMD >/dev/null 2>&1 &
            sleep 1
        fi

        if pgrep -u "$(id -u)" -f "$TRAY_CMD" >/dev/null 2>&1; then
            printf "%b\n" "${GREEN}✓ Tailscale tray icon is running in Quickshell top bar!${RC}"
        fi
    fi
}

# ── Backend State & Helpers ──────────────────────────────────────────────────

tailscaleBackendState() {
    tailscale status --json 2>/dev/null |
        sed -n 's/.*"BackendState"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p'
}

tailscaleIsRunning() {
    [ "$(tailscaleBackendState)" = "Running" ]
}

readSecret() {
    prompt="$1"
    secret=""

    printf "%b" "$prompt"
    if [ -t 0 ]; then
        old_stty=$(stty -g 2>/dev/null || true)
        if [ -n "$old_stty" ]; then
            stty -echo
        fi
        read -r secret
        if [ -n "$old_stty" ]; then
            stty "$old_stty"
            printf "\n"
        fi
    else
        read -r secret
    fi

    READ_SECRET_VALUE="$secret"
}

promptConfiguration() {
    printf "%b\n" "${CYAN}========================================${RC}"
    printf "%b\n" "${CYAN}Tailscale Configuration${RC}"
    printf "%b\n" "${CYAN}========================================${RC}"

    DEFAULT_HOST=$(hostname 2>/dev/null || echo "fedora")
    printf "%b" "${YELLOW}Device hostname in Tailscale [$DEFAULT_HOST]: ${RC}"
    read -r TAILSCALE_HOSTNAME
    TAILSCALE_HOSTNAME="${TAILSCALE_HOSTNAME:-$DEFAULT_HOST}"

    case "$TAILSCALE_HOSTNAME" in
        *[!A-Za-z0-9._-]*)
            printf "%b\n" "${RED}Hostname can only use letters, numbers, dot, underscore, and dash.${RC}"
            exit 1
            ;;
    esac

    printf "%b\n" "${CYAN}Authentication:${RC}"
    printf "%b\n" "${CYAN}  - Press Enter for browser login${RC}"
    printf "%b\n" "${CYAN}  - Paste an auth key for headless/server setup${RC}"
    readSecret "${YELLOW}Auth key (hidden, optional): ${RC}"
    AUTH_TOKEN="$READ_SECRET_VALUE"
}

runTailscaleUp() {
    set -- up --ssh=false
    if [ -n "$TAILSCALE_HOSTNAME" ]; then
        set -- "$@" "--hostname=$TAILSCALE_HOSTNAME"
    fi
    if [ -n "$AUTH_TOKEN" ]; then
        set -- "$@" "--auth-key=$AUTH_TOKEN"
    fi
    tailscale "$@"
}

offerOpenSSHTransport() {
    current_ssh=$(tailscale get ssh 2>/dev/null || true)
    if [ "$current_ssh" = "false" ]; then
        printf "%b\n" "${GREEN}Tailscale SSH is already disabled. Use standard OpenSSH for SSH access.${RC}"
        return 0
    fi

    printf "%s\n" 'The home lab plan uses standard OpenSSH. Verify a fresh LAN key login and keep a recovery console open before changing this setting.'
    printf "%s" 'Type DISABLE to turn off Tailscale SSH on this device, or press Enter to leave its current setting: '
    IFS= read -r ssh_choice || return 0
    if [ "$ssh_choice" = "DISABLE" ]; then
        DISABLE_TAILSCALE_SSH=yes
    fi
}

configureTailscale() {
    if tailscaleIsRunning; then
        return 0
    fi

    if [ -n "$AUTH_TOKEN" ]; then
        printf "%b\n" "${YELLOW}→ Authenticating with auth key...${RC}"
    else
        printf "%b\n" "${YELLOW}→ Starting browser login...${RC}"
    fi

    runTailscaleUp
    printf "%b\n" "${GREEN}✓ Tailscale configured with Tailscale SSH disabled${RC}"
}

askOptionalChanges() {
    DESKTOP_USER="${SUDO_USER:-$USER}"
    if [ -n "$DESKTOP_USER" ] && [ "$DESKTOP_USER" != "root" ]; then
        printf 'Allow %s to manage Tailscale without sudo? [y/N]: ' "$DESKTOP_USER"
        IFS= read -r operator_choice || exit 0
        case "$operator_choice" in
            y|Y|yes|YES) SET_TAILSCALE_OPERATOR=yes ;;
            ''|n|N|no|NO) ;;
            *) printf '%s\n' 'Answer yes or no.' >&2; exit 1 ;;
        esac
    fi

    printf '%s' 'Configure the desktop system tray and login autostart on this user account? [y/N]: '
    IFS= read -r tray_choice || exit 0
    case "$tray_choice" in
        y|Y|yes|YES) CONFIGURE_TRAY=yes ;;
        ''|n|N|no|NO) ;;
        *) printf '%s\n' 'Answer yes or no.' >&2; exit 1 ;;
    esac
}

confirmPlan() {
    printf '\n%s\n' 'Planned Tailscale changes:'
    if [ "$PREVIOUSLY_CONNECTED" = no ]; then
        printf '  Connect this device as %s; standard OpenSSH will be selected and Tailscale SSH will be off.\n' "$TAILSCALE_HOSTNAME"
        if [ -n "$AUTH_TOKEN" ]; then
            printf '%s\n' '  Authenticate with the supplied auth key (value remains hidden).'
        else
            printf '%s\n' '  Start browser-based Tailscale authentication.'
        fi
        if [ ! -x "$(command -v tailscale 2>/dev/null || true)" ] || [ "$FORCE_UPDATE" -eq 1 ]; then
            printf '%s\n' '  Install or update Tailscale using the official installer, with a distro package-manager fallback.'
        fi
    else
        printf '%s\n' '  Keep the existing tailnet enrollment and device hostname.'
        [ "$DISABLE_TAILSCALE_SSH" = yes ] && printf '%s\n' '  Disable the Tailscale SSH feature on this device.'
        [ "$DISABLE_TAILSCALE_SSH" = no ] && printf '%s\n' '  Leave the current Tailscale SSH setting unchanged.'
    fi
    printf '%s\n' '  Ensure the tailscaled system service is enabled and running.'
    [ "$SET_TAILSCALE_OPERATOR" = yes ] && printf '  Set %s as the Tailscale operator.\n' "$DESKTOP_USER"
    [ "$CONFIGURE_TRAY" = yes ] && printf '%s\n' '  Write desktop tray and login-autostart files for the current user.'

    if [ "$PREVIOUSLY_CONNECTED" = no ]; then
        printf '%s' 'Type CONNECT to continue: '
        expected=CONNECT
    else
        printf '%s' 'Type APPLY to continue: '
        expected=APPLY
    fi
    IFS= read -r answer || exit 0
    [ "$answer" = "$expected" ] || {
        printf '%s\n' 'No changes applied.'
        exit 0
    }
}

# ── Status ───────────────────────────────────────────────────────────────────

printStatus() {
    printf "%b\n" "${GREEN}========================================${RC}"
    printf "%b\n" "${GREEN}  Tailscale Setup Complete!${RC}"
    printf "%b\n" "${GREEN}========================================${RC}"

    STATE=$(tailscaleBackendState)
    STATE="${STATE:-unknown}"
    printf "%b\n" "${CYAN}  Backend State  : $STATE${RC}"

    if tailscale status >/dev/null 2>&1; then
        TS_IP=$(tailscale ip -4 2>/dev/null || echo "not connected")
        printf "%b\n" "${CYAN}  Tailscale IP   : $TS_IP${RC}"
    fi

    if [ "$SET_TAILSCALE_OPERATOR" = yes ]; then
        printf "%b\n" "${CYAN}  Operator       : $DESKTOP_USER (selected this run)${RC}"
    else
        printf "%b\n" "${CYAN}  Operator       : unchanged by this run${RC}"
    fi
    if [ "$CONFIGURE_TRAY" = yes ]; then
        printf "%b\n" "${CYAN}  XDG Autostart  : ~/.config/autostart/tailscale-systray.desktop${RC}"
        printf "%b\n" "${CYAN}  ~/.xprofile    : configured for Tailscale tray autostart${RC}"
        if pgrep -u "$(id -u)" -f "tailscale" >/dev/null 2>&1; then
            printf "%b\n" "${CYAN}  System Tray    : active (running in Quickshell top bar)${RC}"
        else
            printf "%b\n" "${CYAN}  System Tray    : configured (starts on login or run 'tailscale-tray')${RC}"
        fi
        printf "%b\n" "${CYAN}  Tray Icon      : minimal Nord SVG (tailscale-connected.svg)${RC}"
    else
        printf "%b\n" "${CYAN}  Desktop tray   : unchanged by this run${RC}"
    fi

    printf "%b\n" "${GREEN}========================================${RC}"
    printf "%b\n" "${CYAN}Useful commands:${RC}"
    printf "%b\n" "${CYAN}  tailscale status       - Check connection & online peers${RC}"
    printf "%b\n" "${CYAN}  tailscale ip           - Show Tailscale IP${RC}"
    printf "%b\n" "${CYAN}  tailscale systray      - Launch system tray icon${RC}"
    printf "%b\n" "${CYAN}  tailscale up           - Connect / authenticate${RC}"
    printf "%b\n" "${CYAN}  tailscale down         - Disconnect${RC}"
    printf "%b\n" "${GREEN}========================================${RC}"
}

# ── Main ─────────────────────────────────────────────────────────────────────

checkEnv
checkEscalationTool
[ -t 0 ] || { printf '%s\n' 'Run Tailscale setup in a terminal so you can choose the connection, SSH mode, operator, and desktop changes.' >&2; exit 1; }

if [ "$TRAY_ONLY" -eq 1 ]; then
    printf '%s' 'Configure desktop tray and login autostart for this user? [y/N]: '
    IFS= read -r tray_choice || exit 0
    case "$tray_choice" in
        y|Y|yes|YES) CONFIGURE_TRAY=yes ;;
        ''|n|N|no|NO) exit 0 ;;
        *) printf '%s\n' 'Answer yes or no.' >&2; exit 1 ;;
    esac
    printf '%s' 'Type APPLY to write the tray and autostart files: '
    IFS= read -r answer || exit 0
    [ "$answer" = APPLY ] || exit 0
    setupTailscaleSystray
    exit 0
fi

if tailscaleIsRunning; then
    PREVIOUSLY_CONNECTED=yes
    CURRENT_IP=$(tailscale ip -4 2>/dev/null || echo "unknown")
    CURRENT_HOST=$(tailscale status --self --json 2>/dev/null |
        sed -n 's/.*"HostName"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
    CURRENT_HOST="${CURRENT_HOST:-$(hostname)}"
    printf '%s\n' "Existing tailnet connection: $CURRENT_HOST ($CURRENT_IP)"
    offerOpenSSHTransport
else
    promptConfiguration
fi

askOptionalChanges
confirmPlan
installTailscale
enableTailscale
if [ "$DISABLE_TAILSCALE_SSH" = yes ]; then
    "$ESCALATION_TOOL" tailscale set --ssh=false
    printf '%b\n' "${GREEN}Tailscale SSH disabled. Test standard OpenSSH from outside the LAN.${RC}"
fi
configureTailscale
if [ "$CONFIGURE_TRAY" = yes ]; then
    setupTailscaleSystray
fi
printStatus
