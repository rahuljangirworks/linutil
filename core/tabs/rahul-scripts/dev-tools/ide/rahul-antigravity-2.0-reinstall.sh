#!/bin/sh -e

# Description: Clean reinstall Antigravity 2.0 from scratch (removes all user data)
# Works on: Arch, Debian, Fedora, openSUSE, Void, Alpine, Solus

. ../../../common-script.sh

checkEnv

APP_NAME="Antigravity 2.0"
INSTALL_DIR="/opt/antigravity"
BIN_LINK="/usr/local/bin/antigravity"
DESKTOP_DIR="$HOME/.local/share/applications"
DESKTOP_FILE="$DESKTOP_DIR/antigravity.desktop"
ICON_DIR="$HOME/.local/share/icons/hicolor/256x256/apps"
ICON_FILE="$ICON_DIR/antigravity-2.0.png"
ICON_URL="https://res.cloudinary.com/utehls4u/image/upload/v1786093093/antigravity_lng1fx.webp"
DOWNLOAD_URL="https://storage.googleapis.com/antigravity-public/antigravity-hub/2.5.0-5471848641724416/linux-x64/Antigravity.tar.gz"

clear 2>/dev/null || true
printf "%b\n" "${CYAN}=================================================================${RC}"
printf "%b\n" "${YELLOW}        Antigravity 2.0 — Clean Reinstall                        ${RC}"
printf "%b\n" "${CYAN}=================================================================${RC}"
printf "%b\n" "${GREEN}  Phase 1: Uninstall old installation + wipe user data${RC}"
printf "%b\n" "${GREEN}  Phase 2: Download & install to /opt/antigravity${RC}"
printf "%b\n" "${GREEN}  Phase 3: Fix sandbox, symlink, icon, desktop entry${RC}"
printf "%b\n" "${CYAN}=================================================================${RC}"
echo ""

# ─── Phase 1: Uninstall & Remove All User Data ──────────────────────────────
phase1_uninstall() {
    printf "%b\n" "${CYAN}━━━ Phase 1: Uninstall & Remove User Data ━━━━━━━━━━━━━━━━━━━━━━━${RC}"

    # Ask user about user data removal
    printf "%b" "${YELLOW}[*] Do you want to remove ALL Antigravity user data (config, cache, settings)? [y/N]: ${RC}"
    read -r remove_data
    case "${remove_data:-N}" in
        y|Y|yes|YES)
            REMOVE_USER_DATA=true
            printf "%b\n" "${GREEN}  → Will remove all user data${RC}"
            ;;
        *)
            REMOVE_USER_DATA=false
            printf "%b\n" "${GREEN}  → Will keep user data${RC}"
            ;;
    esac
    echo ""

    AG_PIDS=$(pgrep -i -x "antigravity" 2>/dev/null || true)
    if [ -n "$AG_PIDS" ]; then
        printf "%b\n" "${YELLOW}[*] Killing running Antigravity processes...${RC}"
        echo "$AG_PIDS" | xargs kill 2>/dev/null || true
        sleep 2
    else
        printf "%b\n" "${GREEN}[✓] No running Antigravity processes found${RC}"
    fi

    if [ -d "$INSTALL_DIR" ]; then
        printf "%b\n" "${YELLOW}[*] Removing install directory: $INSTALL_DIR${RC}"
        if [ -n "$ESCALATION_TOOL" ]; then
            "$ESCALATION_TOOL" rm -rf "$INSTALL_DIR"
        else
            rm -rf "$INSTALL_DIR"
        fi
        
        # Verify it was actually removed
        if [ -d "$INSTALL_DIR" ]; then
            printf "%b\n" "${RED}[✗] Failed to remove install directory: $INSTALL_DIR. Aborting.${RC}"
            exit 1
        fi
    fi

    if [ -L "$BIN_LINK" ] || [ -f "$BIN_LINK" ]; then
        printf "%b\n" "${YELLOW}[*] Removing launcher: $BIN_LINK${RC}"
        if [ -n "$ESCALATION_TOOL" ]; then
            "$ESCALATION_TOOL" rm -f "$BIN_LINK"
        else
            rm -f "$BIN_LINK"
        fi
    fi

    if [ -f "$DESKTOP_FILE" ]; then
        printf "%b\n" "${YELLOW}[*] Removing desktop entry: $DESKTOP_FILE${RC}"
        rm -f "$DESKTOP_FILE"
    fi

    # Only remove user data if user chose yes
    if [ "$REMOVE_USER_DATA" = true ]; then
        printf "%b\n" "${YELLOW}[*] Removing user data...${RC}"

        # Main config directory (Electron/Chromium data)
        for dir in \
            "$HOME/.config/Antigravity" \
            "$HOME/.config/antigravity" \
            "$HOME/.config/antigravity-ide" \
            "$HOME/.config/antigravity-hub"
        do
            if [ -d "$dir" ]; then
                printf "%b\n" "    Removing: $dir${RC}"
                rm -rf "$dir"
            fi
        done

        # Cache directories
        for dir in \
            "$HOME/.cache/antigravity" \
            "$HOME/.cache/antigravity-ide" \
            "$HOME/.cache/Antigravity"
        do
            if [ -d "$dir" ]; then
                printf "%b\n" "    Removing: $dir${RC}"
                rm -rf "$dir"
            fi
        done

        # Local share data
        for dir in \
            "$HOME/.local/share/antigravity" \
            "$HOME/.local/state/antigravity"
        do
            if [ -d "$dir" ]; then
                printf "%b\n" "    Removing: $dir${RC}"
                rm -rf "$dir"
            fi
        done

        # Leftover downloads
        rm -f "$HOME/Downloads/Antigravity.tar.gz" 2>/dev/null || true

        printf "%b\n" "${GREEN}[✓] User data removed${RC}"
    else
        printf "%b\n" "${GREEN}[✓] User data preserved${RC}"
    fi

    if command_exists update-desktop-database; then
        update-desktop-database "$DESKTOP_DIR" >/dev/null 2>&1 || true
    fi

    printf "%b\n" "${GREEN}[✓] Phase 1 complete${RC}"
    echo ""
}

# ─── Phase 2: Download & Install to /opt ───────────────────────────────────
phase2_install() {
    printf "%b\n" "${CYAN}━━━ Phase 2: Download & Install Antigravity 2.0 ━━━━━━━━━━━━━━━━━${RC}"

    TMP_DIR=$(mktemp -d)
    TMP_FILE="$TMP_DIR/Antigravity.tar.gz"

    printf "%b\n" "${YELLOW}[*] Downloading Antigravity 2.0...${RC}"
    printf "%b\n" "${CYAN}    URL: $DOWNLOAD_URL${RC}"

    curl -fL "$DOWNLOAD_URL" -o "$TMP_FILE" || {
        printf "%b\n" "${RED}[✗] Download failed. Check URL or network.${RC}"
        rm -rf "$TMP_DIR"
        return 1
    }

    printf "%b\n" "${YELLOW}[*] Extracting...${RC}"
    tar -xzf "$TMP_FILE" -C "$TMP_DIR" 2>/dev/null || {
        printf "%b\n" "${RED}[✗] Extraction failed.${RC}"
        rm -rf "$TMP_DIR"
        return 1
    }

    EXTRACTED=$(find "$TMP_DIR" -maxdepth 1 -type d -name "Antigravity*" | head -1)
    if [ -z "$EXTRACTED" ]; then
        printf "%b\n" "${RED}[✗] Could not find Antigravity directory after extraction.${RC}"
        rm -rf "$TMP_DIR"
        return 1
    fi

    printf "%b\n" "${YELLOW}[*] Installing to $INSTALL_DIR...${RC}"
    if [ -n "$ESCALATION_TOOL" ]; then
        "$ESCALATION_TOOL" mv "$EXTRACTED" "$INSTALL_DIR"
    else
        mv "$EXTRACTED" "$INSTALL_DIR"
    fi

    rm -rf "$TMP_DIR"

    if [ ! -d "$INSTALL_DIR" ]; then
        printf "%b\n" "${RED}[✗] Installation failed — $INSTALL_DIR not created.${RC}"
        return 1
    fi

    printf "%b\n" "${GREEN}[✓] Antigravity 2.0 installed: $INSTALL_DIR${RC}"
    echo ""
}

# ─── Phase 3: Sandbox Fix, Symlink, Icon, Desktop Entry ──────────────────────
phase3_setup() {
    printf "%b\n" "${CYAN}━━━ Phase 3: Fix Sandbox, Symlink, Icon, Desktop Entry ━━━━━━━━━━${RC}"

    AG_BIN=$(find "$INSTALL_DIR" -maxdepth 2 -type f -name "antigravity" -o -name "Antigravity" | head -1)
    if [ -z "$AG_BIN" ]; then
        printf "%b\n" "${RED}[✗] Could not find antigravity executable in $INSTALL_DIR${RC}"
        return 1
    fi

    SANDBOX="$INSTALL_DIR/chrome-sandbox"
    if [ -f "$SANDBOX" ]; then
        printf "%b\n" "${YELLOW}[*] Fixing Electron sandbox permissions...${RC}"
        if [ -n "$ESCALATION_TOOL" ]; then
            "$ESCALATION_TOOL" chown root:root "$SANDBOX"
            "$ESCALATION_TOOL" chmod 4755 "$SANDBOX"
        else
            chown root:root "$SANDBOX" 2>/dev/null || true
            chmod 4755 "$SANDBOX" 2>/dev/null || true
        fi
        printf "%b\n" "${GREEN}[✓] Sandbox fixed: $SANDBOX${RC}"
    fi

    printf "%b\n" "${YELLOW}[*] Creating symlink: $BIN_LINK -> $AG_BIN${RC}"
    if [ -n "$ESCALATION_TOOL" ]; then
        "$ESCALATION_TOOL" ln -sf "$AG_BIN" "$BIN_LINK"
    else
        ln -sf "$AG_BIN" "$BIN_LINK"
    fi
    printf "%b\n" "${GREEN}[✓] Symlink created: $BIN_LINK${RC}"

    mkdir -p "$ICON_DIR"
    if [ ! -f "$ICON_FILE" ]; then
        printf "%b\n" "${YELLOW}[*] Downloading Antigravity 2.0 icon...${RC}"
        TMP_ICON="$ICON_DIR/antigravity-2.0.tmp"
        curl -fL "$ICON_URL" -o "$TMP_ICON" 2>/dev/null || {
            printf "%b\n" "${YELLOW}[~] Icon download failed, using bundled icon${RC}"
            BUNDLED=$(find "$INSTALL_DIR" -path "*/static/icon.png" -o -path "*/icon.png" 2>/dev/null | head -1)
            if [ -n "$BUNDLED" ]; then
                cp "$BUNDLED" "$ICON_FILE"
            fi
            TMP_ICON=""
        }
        # Convert WebP to PNG if needed
        if [ -n "$TMP_ICON" ] && [ -f "$TMP_ICON" ]; then
            FILE_TYPE=$(file -b "$TMP_ICON" 2>/dev/null || echo "")
            if echo "$FILE_TYPE" | grep -qi "webp"; then
                if command -v ffmpeg >/dev/null 2>&1; then
                    ffmpeg -y -i "$TMP_ICON" "$ICON_FILE" 2>/dev/null || cp "$TMP_ICON" "$ICON_FILE"
                elif command -v convert >/dev/null 2>&1; then
                    convert "$TMP_ICON" "$ICON_FILE" 2>/dev/null || cp "$TMP_ICON" "$ICON_FILE"
                else
                    cp "$TMP_ICON" "$ICON_FILE"
                fi
                rm -f "$TMP_ICON"
            else
                mv "$TMP_ICON" "$ICON_FILE"
            fi
        fi
    fi

    if [ -f "$ICON_FILE" ]; then
        printf "%b\n" "${GREEN}[✓] Icon installed: $ICON_FILE${RC}"
    fi

    mkdir -p "$DESKTOP_DIR"
    cat > "$DESKTOP_FILE" <<EOF
[Desktop Entry]
Type=Application
Name=$APP_NAME
Exec=$AG_BIN
Icon=$ICON_FILE
Terminal=false
Categories=Development;
StartupWMClass=Antigravity
EOF

    if command_exists update-desktop-database; then
        update-desktop-database "$DESKTOP_DIR" >/dev/null 2>&1 || true
    fi

    printf "%b\n" "${GREEN}[✓] Desktop entry written: $DESKTOP_FILE${RC}"
    echo ""
}

# ─── Verify ─────────────────────────────────────────────────────────────────
verify_setup() {
    printf "%b\n" "${CYAN}━━━ Verification ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RC}"

    PASS=true

    if [ -d "$INSTALL_DIR" ]; then
        printf "%b\n" "${GREEN}[✓] Install directory: $INSTALL_DIR${RC}"
    else
        printf "%b\n" "${RED}[✗] Install directory missing${RC}"
        PASS=false
    fi

    if [ -L "$BIN_LINK" ]; then
        printf "%b\n" "${GREEN}[✓] Symlink: $BIN_LINK -> $(readlink "$BIN_LINK")${RC}"
    else
        printf "%b\n" "${RED}[✗] Symlink missing: $BIN_LINK${RC}"
        PASS=false
    fi

    if [ -f "$DESKTOP_FILE" ]; then
        printf "%b\n" "${GREEN}[✓] Desktop entry: $DESKTOP_FILE${RC}"
    else
        printf "%b\n" "${RED}[✗] Desktop entry missing${RC}"
        PASS=false
    fi

    if [ -f "$ICON_FILE" ]; then
        printf "%b\n" "${GREEN}[✓] Icon: $ICON_FILE${RC}"
    fi

    SANDBOX="$INSTALL_DIR/chrome-sandbox"
    if [ -f "$SANDBOX" ]; then
        PERMS=$(stat -c "%a" "$SANDBOX" 2>/dev/null || stat -f "%Lp" "$SANDBOX" 2>/dev/null || echo "unknown")
        if [ "$PERMS" = "4755" ]; then
            printf "%b\n" "${GREEN}[✓] Sandbox permissions: $PERMS (correct)${RC}"
        fi
    fi

    echo ""
    if [ "$PASS" = true ]; then
        printf "%b\n" "${GREEN}=================================================================${RC}"
        printf "%b\n" "${GREEN}  Antigravity 2.0 installed successfully!${RC}"
        printf "%b\n" "${CYAN}  Launch: antigravity${RC}"
        printf "%b\n" "${CYAN}  Or find 'Antigravity 2.0' in app menu${RC}"
        printf "%b\n" "${GREEN}=================================================================${RC}"
    else
        printf "%b\n" "${RED}=================================================================${RC}"
        printf "%b\n" "${RED}  Installation completed with warnings. Check output above.${RC}"
        printf "%b\n" "${RED}=================================================================${RC}"
    fi
}

# ─── Main ───────────────────────────────────────────────────────────────────
phase1_uninstall
phase2_install
phase3_setup
verify_setup
