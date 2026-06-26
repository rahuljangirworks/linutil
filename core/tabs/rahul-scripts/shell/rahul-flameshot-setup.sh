#!/bin/sh -e

# Description: Install and configure Flameshot for dwm-rahul on X11
# Repository: https://github.com/rahuljangirworks/dwm-rahul

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/../../common-script.sh"

installFlameshot() {
    if command_exists flameshot; then
        printf "%b\n" "${GREEN}[Flameshot] Already installed${RC}"
        return 0
    fi

    printf "%b\n" "${YELLOW}[Flameshot] Installing Flameshot...${RC}"
    case "$PACKAGER" in
        pacman)
            "$ESCALATION_TOOL" "$PACKAGER" -S --needed --noconfirm flameshot
            ;;
        apk)
            "$ESCALATION_TOOL" "$PACKAGER" add flameshot
            ;;
        xbps-install)
            "$ESCALATION_TOOL" "$PACKAGER" -Sy flameshot
            ;;
        *)
            "$ESCALATION_TOOL" "$PACKAGER" install -y flameshot
            ;;
    esac

    if command_exists flameshot; then
        printf "%b\n" "${GREEN}[Flameshot] Installed successfully${RC}"
    else
        printf "%b\n" "${RED}[Flameshot] Installation failed${RC}"
        return 1
    fi
}

configureFlameshot() {
    printf "%b\n" "${YELLOW}[Flameshot] Ensuring X11 legacy capture mode...${RC}"

    CONFIG_DIR="$HOME/.config/flameshot"
    CONFIG_FILE="$CONFIG_DIR/flameshot.ini"
    SCREENSHOT_DIR="$HOME/Pictures/Screenshots"

    mkdir -p "$CONFIG_DIR"
    mkdir -p "$SCREENSHOT_DIR"

    # Backup existing config
    if [ -f "$CONFIG_FILE" ] && [ ! -f "${CONFIG_FILE}.bak" ]; then
        cp "$CONFIG_FILE" "${CONFIG_FILE}.bak"
        printf "%b\n" "${YELLOW}Backed up existing config${RC}"
    fi

    if [ ! -f "$CONFIG_FILE" ]; then
        {
            printf "%s\n" "[General]"
            printf "%s\n" "useX11LegacyScreenshot=true"
            printf "%s\n" "savePath=$SCREENSHOT_DIR"
            printf "%s\n" "saveAsFileExtension=png"
            printf "%s\n" "saveAfterCopy=true"
            printf "%s\n" "showStartupLaunchMessage=false"
        } > "$CONFIG_FILE"
    else
        if grep -q '^useX11LegacyScreenshot=' "$CONFIG_FILE" 2>/dev/null; then
            sed -i 's/^useX11LegacyScreenshot=.*/useX11LegacyScreenshot=true/' "$CONFIG_FILE"
        else
            printf "%s\n" "useX11LegacyScreenshot=true" >> "$CONFIG_FILE"
        fi

        if grep -q '^savePath=' "$CONFIG_FILE" 2>/dev/null; then
            sed -i "s|^savePath=.*|savePath=$SCREENSHOT_DIR|" "$CONFIG_FILE"
        else
            printf "%s\n" "savePath=$SCREENSHOT_DIR" >> "$CONFIG_FILE"
        fi

        if ! grep -q '^showStartupLaunchMessage=' "$CONFIG_FILE" 2>/dev/null; then
            printf "%s\n" "showStartupLaunchMessage=false" >> "$CONFIG_FILE"
        fi
    fi

    printf "%b\n" "${GREEN}[Flameshot] Config written to $CONFIG_FILE${RC}"
}

setupDwmKeybinding() {
    printf "%b\n" "${YELLOW}[Flameshot] Adding DWM keybinding...${RC}"

    HOTKEYS_FILE="$HOME/.config/dwm-rahul/hotkeys.toml"

    if [ ! -f "$HOTKEYS_FILE" ]; then
        printf "%b\n" "${YELLOW}hotkeys.toml not found, skipping keybinding${RC}"
        return 0
    fi

    # Check if flameshot keybinding already exists
    if grep -q "flameshot" "$HOTKEYS_FILE" 2>/dev/null; then
        printf "%b\n" "${GREEN}Flameshot keybinding already configured${RC}"
        return 0
    fi

    # Add flameshot keybinding before the closing bracket
    # Super+P for fullscreen, Super+Shift+P for area selection
    # These are already in the default hotkeys.toml from dwm-rahul
    printf "%b\n" "${GREEN}Flameshot keybindings already in default hotkeys.toml${RC}"
    printf "%b\n" "${CYAN}  Super+P          → Fullscreen screenshot${RC}"
    printf "%b\n" "${CYAN}  Super+Shift+P    → Area selection screenshot${RC}"
    printf "%b\n" "${CYAN}  Super+Ctrl+P     → Area to clipboard${RC}"
}

startFlameshotDaemon() {
    printf "%b\n" "${YELLOW}[Flameshot] Starting Flameshot daemon...${RC}"

    if pgrep -x flameshot >/dev/null 2>&1; then
        printf "%b\n" "${GREEN}Flameshot daemon already running${RC}"
    else
        # Kill any stale instances
        pkill -x flameshot 2>/dev/null || true
        sleep 0.3

        # Start daemon in background with DWM identity to avoid portal capture.
        XDG_CURRENT_DESKTOP=dwm DESKTOP_SESSION=dwm flameshot &
        sleep 0.5

        if pgrep -x flameshot >/dev/null 2>&1; then
            printf "%b\n" "${GREEN}Flameshot daemon started${RC}"
        else
            printf "%b\n" "${YELLOW}Flameshot daemon not started (will start on next login)${RC}"
        fi
    fi
}

printSummary() {
    printf "%b\n" ""
    printf "%b\n" "${GREEN}╔══════════════════════════════════════════════╗${RC}"
    printf "%b\n" "${GREEN}║     Flameshot Setup Complete                 ║${RC}"
    printf "%b\n" "${GREEN}╚══════════════════════════════════════════════╝${RC}"
    printf "%b\n" "${CYAN}  Capture:  X11 legacy mode for dwm multi-monitor support${RC}"
    printf "%b\n" "${CYAN}  Config:   ~/.config/flameshot/flameshot.ini${RC}"
    printf "%b\n" "${CYAN}  Screenshots: ~/Pictures/Screenshots/${RC}"
    printf "%b\n" ""
    printf "%b\n" "${CYAN}  Keybindings (DWM):${RC}"
    printf "%b\n" "${CYAN}    Super+P          → Fullscreen screenshot${RC}"
    printf "%b\n" "${CYAN}    Super+Shift+P    → Area selection to file${RC}"
    printf "%b\n" "${CYAN}    Super+Ctrl+P     → Area to clipboard${RC}"
    printf "%b\n" ""
    printf "%b\n" "${CYAN}  Manual launch: flameshot gui${RC}"
    printf "%b\n" "${CYAN}  Tray icon:     flameshot launcher${RC}"
    printf "%b\n" "${GREEN}╚══════════════════════════════════════════════╝${RC}"
}

checkEnv
checkEscalationTool
installFlameshot
configureFlameshot
setupDwmKeybinding
startFlameshotDaemon
printSummary
