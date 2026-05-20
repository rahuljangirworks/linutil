#!/bin/sh -e

# Description: Clean reinstall Antigravity IDE from scratch (removes all user data)
# Works on: Arch, Debian, Fedora, openSUSE, Void, Alpine, Solus

. ../common-script.sh

checkEnv

APP_NAME="Antigravity IDE"
INSTALL_DIR="$HOME/.local/share/antigravity"
APPIMAGE_PATH="$INSTALL_DIR/Antigravity.AppImage"
DESKTOP_DIR="$HOME/.local/share/applications"
DESKTOP_FILE="$DESKTOP_DIR/antigravity-ide.desktop"
ICON_DIR="$HOME/.local/share/icons/hicolor/256x256/apps"
ICON_FILE="$ICON_DIR/antigravity-icon.png"
BIN_DIR="$HOME/.local/bin"
BIN_PATH="$BIN_DIR/antigravity"

# Download URL & icon URL
DOWNLOAD_URL="https://storage.googleapis.com/antigravity-public/antigravity-hub/2.0.1-6566078776737792/linux-x64/Antigravity.tar.gz"
ICON_URL="https://antigravity.google/assets/image/brand/antigravity-icon__full-color.png"

clear 2>/dev/null || true
printf "%b\n" "${CYAN}=================================================================${RC}"
printf "%b\n" "${YELLOW}        Antigravity IDE — Clean Reinstall                        ${RC}"
printf "%b\n" "${CYAN}=================================================================${RC}"
printf "%b\n" "${GREEN}  Phase 1: Uninstall IDE + wipe ALL user data${RC}"
printf "%b\n" "${GREEN}  Phase 2: Fresh install from scratch${RC}"
printf "%b\n" "${GREEN}  Phase 3: Desktop entry with icon${RC}"
printf "%b\n" "${CYAN}=================================================================${RC}"
echo ""

# ─── Phase 1: Uninstall & Remove All User Data ──────────────────────────────
phase1_uninstall() {
    printf "%b\n" "${CYAN}━━━ Phase 1: Uninstall & Remove User Data ━━━━━━━━━━━━━━━━━━━━━━━${RC}"

    # Kill running instances (exclude this script itself)
    AG_PIDS=$(pgrep -f "Antigravity.AppImage" 2>/dev/null || true)
    if [ -n "$AG_PIDS" ]; then
        printf "%b\n" "${YELLOW}[*] Killing running Antigravity processes...${RC}"
        echo "$AG_PIDS" | xargs kill 2>/dev/null || true
        sleep 2
    else
        printf "%b\n" "${GREEN}[✓] No running Antigravity processes found${RC}"
    fi

    # Remove AppImage / install directory
    if [ -d "$INSTALL_DIR" ]; then
        printf "%b\n" "${YELLOW}[*] Removing install directory: $INSTALL_DIR${RC}"
        rm -rf "$INSTALL_DIR"
    fi

    # Remove desktop entry
    if [ -f "$DESKTOP_FILE" ]; then
        printf "%b\n" "${YELLOW}[*] Removing desktop entry: $DESKTOP_FILE${RC}"
        rm -f "$DESKTOP_FILE"
    fi

    # Remove icon
    if [ -f "$ICON_FILE" ]; then
        printf "%b\n" "${YELLOW}[*] Removing icon: $ICON_FILE${RC}"
        rm -f "$ICON_FILE"
    fi

    # Remove fast launcher symlink/binary
    if [ -f "$BIN_PATH" ]; then
        printf "%b\n" "${YELLOW}[*] Removing launcher: $BIN_PATH${RC}"
        rm -f "$BIN_PATH"
    fi

    # Remove Antigravity user data directories (POSIX-compatible, no arrays)
    for dir in \
        "$HOME/.config/antigravity" \
        "$HOME/.config/antigravity-ide" \
        "$HOME/.config/antigravity-hub" \
        "$HOME/.local/share/antigravity" \
        "$HOME/.cache/antigravity" \
        "$HOME/.cache/antigravity-ide" \
        "$HOME/.local/state/antigravity"
    do
        if [ -d "$dir" ]; then
            printf "%b\n" "${YELLOW}[*] Removing user data: $dir${RC}"
            rm -rf "$dir"
        fi
    done

    # Remove Electron/Chromium cache that Antigravity may use
    for dir in \
        "$HOME/.config/Antigravity" \
        "$HOME/.config/Antigravity IDE" \
        "$HOME/.cache/Antigravity" \
        "$HOME/.cache/Antigravity IDE"
    do
        if [ -d "$dir" ]; then
            printf "%b\n" "${YELLOW}[*] Removing Electron data: $dir${RC}"
            rm -rf "$dir"
        fi
    done

    # Remove any leftover tarballs/downloads
    rm -f "$HOME/Downloads/Antigravity.tar.gz" 2>/dev/null || true

    # Update desktop database
    if command_exists update-desktop-database; then
        update-desktop-database "$DESKTOP_DIR" >/dev/null 2>&1 || true
    fi

    printf "%b\n" "${GREEN}[✓] Phase 1 complete — all Antigravity data removed${RC}"
    echo ""
}

# ─── Phase 2: Download & Install ────────────────────────────────────────────
phase2_install() {
    printf "%b\n" "${CYAN}━━━ Phase 2: Download & Install Antigravity IDE ━━━━━━━━━━━━━━━━━${RC}"

    mkdir -p "$INSTALL_DIR" "$BIN_DIR" "$DESKTOP_DIR" "$ICON_DIR"

    # Check if already installed
    if [ -f "$APPIMAGE_PATH" ]; then
        printf "%b\n" "${GREEN}[✓] Antigravity already installed at $APPIMAGE_PATH${RC}"
        printf "%b\n" "${YELLOW}[*] Skipping download (delete $INSTALL_DIR to force reinstall)${RC}"
        echo ""
        return 0
    fi

    TMP_FILE="$INSTALL_DIR/Antigravity.tar.gz.download"

    printf "%b\n" "${YELLOW}[*] Downloading Antigravity IDE...${RC}"
    printf "%b\n" "${CYAN}    URL: $DOWNLOAD_URL${RC}"
    curl -fL "$DOWNLOAD_URL" -o "$TMP_FILE" || {
        printf "%b\n" "${RED}[✗] Download failed. Check URL or network.${RC}"
        rm -f "$TMP_FILE"
        return 1
    }

    printf "%b\n" "${YELLOW}[*] Extracting...${RC}"
    tar -xzf "$TMP_FILE" -C "$INSTALL_DIR" --strip-components=1 2>/dev/null || {
        # Fallback: extract without strip if structure differs
        tar -xzf "$TMP_FILE" -C "$INSTALL_DIR" 2>/dev/null || {
            printf "%b\n" "${RED}[✗] Extraction failed.${RC}"
            rm -f "$TMP_FILE"
            return 1
        }
    }
    rm -f "$TMP_FILE"

    # Find the actual executable after extraction
    if [ ! -f "$APPIMAGE_PATH" ]; then
        FOUND=$(find "$INSTALL_DIR" -maxdepth 2 -type f \( -name "*.AppImage" -o -name "antigravity" -o -name "Antigravity" -o -name "antigravity-ide" \) 2>/dev/null | head -1)
        if [ -n "$FOUND" ]; then
            mv "$FOUND" "$APPIMAGE_PATH"
        else
            printf "%b\n" "${RED}[✗] Could not find executable after extraction.${RC}"
            printf "%b\n" "${YELLOW}    Extracted contents:${RC}"
            ls -la "$INSTALL_DIR"
            return 1
        fi
    fi

    chmod +x "$APPIMAGE_PATH"
    printf "%b\n" "${GREEN}[✓] Antigravity IDE installed: $APPIMAGE_PATH${RC}"
    echo ""
}

# ─── Phase 3: Desktop Entry & Icon ──────────────────────────────────────────
phase3_desktop() {
    printf "%b\n" "${CYAN}━━━ Phase 3: Desktop Entry & Icon ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RC}"

    # Download icon
    if [ ! -f "$ICON_FILE" ]; then
        printf "%b\n" "${YELLOW}[*] Downloading Antigravity icon...${RC}"
        curl -fL "$ICON_URL" -o "$ICON_FILE" 2>/dev/null || {
            printf "%b\n" "${YELLOW}[~] Icon download failed, skipping icon.${RC}"
        }
        printf "%b\n" "${GREEN}[✓] Icon installed: $ICON_FILE${RC}"
    else
        printf "%b\n" "${GREEN}[✓] Icon already exists: $ICON_FILE${RC}"
    fi

    # Write desktop entry
    cat > "$DESKTOP_FILE" <<EOF
[Desktop Entry]
Type=Application
Name=$APP_NAME
Comment=Antigravity IDE — AI-powered coding environment
Exec=$APPIMAGE_PATH
Icon=$ICON_FILE
Terminal=false
Categories=Development;IDE;
StartupNotify=true
StartupWMClass=antigravity
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

    if [ -x "$APPIMAGE_PATH" ]; then
        printf "%b\n" "${GREEN}[✓] AppImage executable: $APPIMAGE_PATH${RC}"
    else
        printf "%b\n" "${RED}[✗] AppImage not found or not executable${RC}"
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
    else
        printf "%b\n" "${RED}[✗] Icon missing${RC}"
        PASS=false
    fi

    # Verify no old user data remains
    OLD_DATA_FOUND=false
    for dir in "$HOME/.config/antigravity" "$HOME/.config/antigravity-ide" "$HOME/.config/antigravity-hub"; do
        if [ -d "$dir" ]; then
            OLD_DATA_FOUND=true
            printf "%b\n" "${RED}[✗] Old user data still exists: $dir${RC}"
        fi
    done

    if [ "$OLD_DATA_FOUND" = false ]; then
        printf "%b\n" "${GREEN}[✓] No old user data found — clean install confirmed${RC}"
    fi

    echo ""
    if [ "$PASS" = true ]; then
        printf "%b\n" "${GREEN}=================================================================${RC}"
        printf "%b\n" "${GREEN}  Antigravity IDE clean reinstall complete!${RC}"
        printf "%b\n" "${CYAN}  Launch: antigravity  (or find 'Antigravity IDE' in app menu)${RC}"
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
phase3_desktop
verify_setup
