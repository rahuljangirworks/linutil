#!/bin/sh -e

# Description: Install caffeine-ng (screen inhibitor tray app) and configure
#              it to start silently in the background after login.
#              caffeine-ng lets you toggle sleep/lock prevention from the tray.
#              Works on any WM (DWM, i3, bspwm, etc.) - NOT the GNOME extension.
# Rerunnable:  Yes - skips completed steps

. ../../common-script.sh

CAFFEINE_BIN=""
CAFFEINE_BIN_PATH=""
CAFFEINE_AUTOSTART_DIR="$HOME/.config/autostart"
CAFFEINE_SCHEMA_DIR="$HOME/.local/share/glib-2.0/schemas"

detectCaffeineBin() {
    if command_exists caffeine; then
        CAFFEINE_BIN="caffeine"
    elif command_exists caffeine-ng; then
        CAFFEINE_BIN="caffeine-ng"
    else
        CAFFEINE_BIN=""
    fi
    if [ -n "$CAFFEINE_BIN" ]; then
        CAFFEINE_BIN_PATH="$(command -v "$CAFFEINE_BIN")"
    fi
}

installRuntimeDeps() {
    # gobject-introspection / GTK cannot be built reliably inside a venv, so the
    # runtime bindings must come from the distro package manager.
    printf "%b\n" "${YELLOW}Installing runtime dependencies...${RC}"
    case "$PACKAGER" in
        pacman)      "$ESCALATION_TOOL" "$PACKAGER" -S --needed --noconfirm python-gobject gtk3 libnotify ;;
        apt-get|nala) "$ESCALATION_TOOL" "$PACKAGER" install -y python3-gi python3-gi-cairo gir1.2-gtk-3.0 libnotify4 ;;
        dnf|yum)     "$ESCALATION_TOOL" "$PACKAGER" install -y python3-gobject gtk3 libnotify ;;
        zypper)      "$ESCALATION_TOOL" zypper install -y python3-gobject python3-gobject-cairo gtk3 libnotify-tools ;;
        apk)         "$ESCALATION_TOOL" "$PACKAGER" add py3-gobject3 gtk3 libnotify ;;
        xbps-install) "$ESCALATION_TOOL" "$PACKAGER" -S python3-gobject gtk3 libnotify ;;
        eopkg)       "$ESCALATION_TOOL" "$PACKAGER" install python3-gobject gtk3 libnotify ;;
    esac
}

ensurePipx() {
    if command_exists pipx; then
        return 0
    fi
    printf "%b\n" "${YELLOW}Installing pipx...${RC}"
    # Prefer a distro package, fall back to 'pip install --user' (no root needed).
    case "$PACKAGER" in
        pacman)       "$ESCALATION_TOOL" "$PACKAGER" -S --needed --noconfirm pipx ;;
        apt-get|nala) "$ESCALATION_TOOL" "$PACKAGER" install -y pipx ;;
        dnf|yum)      "$ESCALATION_TOOL" "$PACKAGER" install -y pipx ;;
        zypper)       "$ESCALATION_TOOL" zypper install -y pipx ;;
        apk)          "$ESCALATION_TOOL" "$PACKAGER" add pipx ;;
        xbps-install) "$ESCALATION_TOOL" "$PACKAGER" -S pipx ;;
        eopkg)        "$ESCALATION_TOOL" "$PACKAGER" install pipx ;;
        *) : ;;
    esac
    if ! command_exists pipx; then
        if ! command_exists pip; then
            "$ESCALATION_TOOL" "$PACKAGER" install -y python3-pip 2>/dev/null || true
        fi
        if command_exists pip; then
            pip install --user pipx
        else
            printf "%b\n" "${RED}✗ Could not install pipx (pip unavailable)${RC}"
            exit 1
        fi
    fi
}

installViaPipx() {
    printf "%b\n" "${YELLOW}→ caffeine-ng is not packaged for $PACKAGER - installing via pipx${RC}"
    installRuntimeDeps
    ensurePipx
    export PATH="$HOME/.local/bin:$PATH"
    if [ -d "$HOME/.local/share/pipx/venvs/caffeine-ng" ]; then
        printf "%b\n" "${GREEN}✓ caffeine-ng pipx environment already present${RC}"
    else
        pipx install --system-site-packages caffeine-ng
    fi
}

installCaffeineNg() {
    detectCaffeineBin
    if [ -n "$CAFFEINE_BIN" ]; then
        printf "%b\n" "${GREEN}✓ caffeine-ng already installed ($CAFFEINE_BIN)${RC}"
        return 0
    fi

    printf "%b\n" "${YELLOW}Installing caffeine-ng...${RC}"

    case "$PACKAGER" in
        pacman)
            # Arch ships caffeine-ng in the AUR.
            checkAURHelper
            "$AUR_HELPER" -S --needed --noconfirm caffeine-ng
            ;;
        *)
            # caffeine-ng is not in the main repos of Fedora/Debian/openSUSE/etc.
            # (those that have 'caffeine' ship the legacy GNOME applet), so the
            # reliable cross-distro path is pipx.
            installViaPipx
            ;;
    esac

    # pipx places the binary under ~/.local/bin; make sure it is on PATH.
    export PATH="$HOME/.local/bin:$PATH"
    detectCaffeineBin
    if [ -z "$CAFFEINE_BIN" ]; then
        printf "%b\n" "${RED}✗ Failed to install caffeine-ng${RC}"
        exit 1
    fi
    printf "%b\n" "${GREEN}✓ caffeine-ng installed ($CAFFEINE_BIN -> $CAFFEINE_BIN_PATH)${RC}"
}

installSchema() {
    # pipx installs the GSettings schema inside its venv; the running app needs
    # it on the user schema path or it crashes on launch ("Settings schema ... is
    # not installed").
    SCHEMA_FILE="$(find "$HOME/.local/share/pipx/venvs" -name 'net.launchpad.caffeine.gschema.xml' 2>/dev/null | head -n 1)"
    if [ -z "$SCHEMA_FILE" ]; then
        return 0
    fi
    mkdir -p "$CAFFEINE_SCHEMA_DIR"
    cp "$SCHEMA_FILE" "$CAFFEINE_SCHEMA_DIR/"
    if glib-compile-schemas "$CAFFEINE_SCHEMA_DIR" 2>/dev/null; then
        printf "%b\n" "${GREEN}✓ GSettings schema installed${RC}"
    else
        "$ESCALATION_TOOL" glib-compile-schemas "$CAFFEINE_SCHEMA_DIR"
        printf "%b\n" "${GREEN}✓ GSettings schema installed${RC}"
    fi
}

setupAutostart() {
    printf "%b\n" "${YELLOW}Configuring caffeine-ng autostart...${RC}"

    if [ -z "$CAFFEINE_BIN" ]; then
        detectCaffeineBin
    fi
    if [ -z "$CAFFEINE_BIN" ]; then
        printf "%b\n" "${YELLOW}→ caffeine binary not found - skipping autostart${RC}"
        return 0
    fi

    mkdir -p "$CAFFEINE_AUTOSTART_DIR"
    AUTOSTART_FILE="$CAFFEINE_AUTOSTART_DIR/caffeine.desktop"

    # Determine a sensible startup delay.
    # On Fedora / GNOME the tray (StatusNotifier) is registered by gnome-shell
    # only after the session is fully up, so a short delay prevents the icon
    # from silently vanishing on first login.
    STARTUP_DELAY=8

    # On non-GNOME WMs (DWM, i3, bspwm, …) the tray is usually ready sooner;
    # keep the delay but use bash so the sleep runs without a terminal window.
    EXEC_CMD="bash -c 'sleep ${STARTUP_DELAY} && ${CAFFEINE_BIN_PATH}'"

    cat > "$AUTOSTART_FILE" <<EOF
[Desktop Entry]
Type=Application
Name=Caffeine
Comment=Prevent the computer from suspending or locking the screen
Exec=$EXEC_CMD
Terminal=false
StartupNotify=false
Hidden=false
Categories=Utility;
X-GNOME-Autostart-enabled=true
X-GNOME-Autostart-Delay=0
EOF
    chmod 644 "$AUTOSTART_FILE"
    printf "%b\n" "${GREEN}✓ autostart entry written at $AUTOSTART_FILE (silent tray, ${STARTUP_DELAY}s delay)${RC}"
}

printStatus() {
    printf "%b\n" "${GREEN}========================================${RC}"
    printf "%b\n" "${GREEN}  caffeine-ng Setup Complete!${RC}"
    printf "%b\n" "${GREEN}========================================${RC}"
    printf "%b\n" "${CYAN}  Binary    : $CAFFEINE_BIN${RC}"
    printf "%b\n" "${CYAN}  Location  : $CAFFEINE_BIN_PATH${RC}"
    printf "%b\n" "${CYAN}  Usage     : click the tray cup to toggle sleep prevention${RC}"
    printf "%b\n" "${CYAN}  Autostart : $CAFFEINE_AUTOSTART_DIR/caffeine.desktop${RC}"
    printf "%b\n" "${GREEN}========================================${RC}"
}

checkEnv
checkEscalationTool
installCaffeineNg
installSchema
setupAutostart
printStatus
