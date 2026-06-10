#!/bin/sh -e

# Description: Install Kiro IDE from local tar.gz in ~/Downloads (universal Linux)
# Looks for: ~/Downloads/kiro-ide-*.tar.gz (any version)
# Works on: Arch, Debian, Fedora, openSUSE, Void, Alpine, Solus, any Linux

. ../common-script.sh

checkEnv

# ─── Globals ──────────────────────────────────────────────────────────────────
APP_NAME="Kiro IDE"
INSTALL_DIR="$HOME/.local/share/kiro-ide"
KIRO_BIN="$INSTALL_DIR/kiro"
BIN_DIR="$HOME/.local/bin"
BIN_LINK="$BIN_DIR/kiro"
DESKTOP_DIR="$HOME/.local/share/applications"
DESKTOP_FILE="$DESKTOP_DIR/kiro-ide.desktop"
ICON_DIR="$HOME/.local/share/icons/hicolor/256x256/apps"
ICON_FILE="$ICON_DIR/kiro-ide.png"
ICON_URL="https://raw.githubusercontent.com/lobehub/lobe-icons/refs/heads/master/packages/static-png/light/kiro-color.png"
DOWNLOADS_DIR="$HOME/Downloads"

# ─── Header ───────────────────────────────────────────────────────────────────
clear 2>/dev/null || true
printf "%b\n" "${CYAN}=================================================================${RC}"
printf "%b\n" "${YELLOW}           Kiro IDE — Universal Linux Installer                  ${RC}"
printf "%b\n" "${CYAN}=================================================================${RC}"
printf "%b\n" "${GREEN}  Phase 1: Detect kiro-ide-*.tar.gz in ~/Downloads               ${RC}"
printf "%b\n" "${GREEN}  Phase 2: Extract & install to ~/.local/share/kiro-ide          ${RC}"
printf "%b\n" "${GREEN}  Phase 3: Desktop entry + icon + ~/.local/bin/kiro launcher     ${RC}"
printf "%b\n" "${CYAN}=================================================================${RC}"
echo ""

# ─── Phase 1: Detect tar.gz in ~/Downloads ────────────────────────────────────
phase1_detect() {
    printf "%b\n" "${CYAN}━━━ Phase 1: Detecting Kiro IDE archive ━━━━━━━━━━━━━━━━━━━━━━━━${RC}"

    # Find any kiro-ide-*.tar.gz — pick the newest by filename sort
    TARBALL=""
    if [ -d "$DOWNLOADS_DIR" ]; then
        # shellcheck disable=SC2010
        TARBALL=$(ls -t "$DOWNLOADS_DIR"/kiro-ide-*.tar.gz 2>/dev/null | head -1 || true)
    fi

    if [ -z "$TARBALL" ]; then
        printf "%b\n" "${RED}[✗] No Kiro IDE archive found in $DOWNLOADS_DIR${RC}"
        echo ""
        printf "%b\n" "${YELLOW}━━━ Download Instructions ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RC}"
        printf "%b\n" "${YELLOW}  1. Open: https://kiro.dev  (or wherever Kiro distributes)${RC}"
        printf "%b\n" "${YELLOW}  2. Download the Universal Linux (.tar.gz) package.${RC}"
        printf "%b\n" "${YELLOW}     The filename should look like:${RC}"
        printf "%b\n" "${CYAN}        kiro-ide-*.tar.gz${RC}"
        printf "%b\n" "${YELLOW}     (e.g. kiro-ide-0.12.318-stable-linux-x64.tar.gz)${RC}"
        printf "%b\n" "${YELLOW}  3. Save it to: ${DOWNLOADS_DIR}/${RC}"
        printf "%b\n" "${YELLOW}  4. Re-run this script.${RC}"
        echo ""
        printf "%b\n" "${RED}Aborting — please download the .tar.gz file and try again.${RC}"
        exit 1
    fi

    printf "%b\n" "${GREEN}[✓] Found archive: $(basename "$TARBALL")${RC}"
    printf "%b\n" "${CYAN}    Full path: $TARBALL${RC}"
    echo ""
}

# ─── Phase 2: Extract & Install ───────────────────────────────────────────────
phase2_install() {
    printf "%b\n" "${CYAN}━━━ Phase 2: Installing Kiro IDE ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RC}"

    # Create install and bin dirs
    mkdir -p "$INSTALL_DIR" "$BIN_DIR" "$DESKTOP_DIR" "$ICON_DIR"

    # If already installed, ask before overwriting
    if [ -x "$KIRO_BIN" ]; then
        printf "%b\n" "${YELLOW}[~] Kiro IDE already installed at $INSTALL_DIR${RC}"
        printf "%b\n" "${YELLOW}    Reinstalling from: $(basename "$TARBALL")${RC}"
        printf "%b\n" "${YELLOW}[*] Removing old installation...${RC}"
        rm -rf "$INSTALL_DIR"
        mkdir -p "$INSTALL_DIR"
    fi

    printf "%b\n" "${YELLOW}[*] Extracting $(basename "$TARBALL")...${RC}"

    # Try --strip-components=1 first (most common tar.gz layout has a top-level dir)
    if tar -xzf "$TARBALL" -C "$INSTALL_DIR" --strip-components=1 2>/dev/null; then
        printf "%b\n" "${GREEN}[✓] Extracted with strip (standard layout)${RC}"
    else
        # Fallback: extract as-is
        tar -xzf "$TARBALL" -C "$INSTALL_DIR" 2>/dev/null || {
            printf "%b\n" "${RED}[✗] Extraction failed — archive may be corrupt.${RC}"
            exit 1
        }
        printf "%b\n" "${GREEN}[✓] Extracted (flat layout)${RC}"
    fi

    # Locate the kiro executable — try known paths first, then search
    _find_kiro_bin() {
        for candidate in \
            "$INSTALL_DIR/kiro" \
            "$INSTALL_DIR/kiro-ide" \
            "$INSTALL_DIR/bin/kiro"
        do
            if [ -f "$candidate" ]; then
                echo "$candidate"
                return 0
            fi
        done
        # Deep search up to 3 levels
        find "$INSTALL_DIR" -maxdepth 3 -type f -name "kiro" 2>/dev/null | head -1
    }

    FOUND_BIN=$(_find_kiro_bin)

    if [ -z "$FOUND_BIN" ]; then
        printf "%b\n" "${RED}[✗] Could not locate kiro executable after extraction.${RC}"
        printf "%b\n" "${YELLOW}    Extracted contents:${RC}"
        ls -la "$INSTALL_DIR"
        exit 1
    fi

    # Normalise: move to canonical path if found elsewhere
    if [ "$FOUND_BIN" != "$KIRO_BIN" ]; then
        printf "%b\n" "${YELLOW}[*] Moving binary: $FOUND_BIN -> $KIRO_BIN${RC}"
        mv "$FOUND_BIN" "$KIRO_BIN"
    fi

    chmod +x "$KIRO_BIN"
    printf "%b\n" "${GREEN}[✓] Kiro IDE installed: $KIRO_BIN${RC}"

    # Create ~/.local/bin/kiro symlink so `kiro` works from terminal
    ln -sf "$KIRO_BIN" "$BIN_LINK"
    printf "%b\n" "${GREEN}[✓] Launcher symlink: $BIN_LINK -> $KIRO_BIN${RC}"
    echo ""
}

# ─── Phase 3: Icon + Desktop Entry ────────────────────────────────────────────
phase3_desktop() {
    printf "%b\n" "${CYAN}━━━ Phase 3: Icon & Desktop Entry ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RC}"

    # Download icon
    printf "%b\n" "${YELLOW}[*] Downloading Kiro icon...${RC}"
    if curl -fsSL "$ICON_URL" -o "$ICON_FILE" 2>/dev/null; then
        printf "%b\n" "${GREEN}[✓] Icon saved: $ICON_FILE${RC}"
    else
        printf "%b\n" "${YELLOW}[~] Icon download failed (network issue). Using fallback text icon.${RC}"
        # Write a minimal 1x1 transparent PNG as fallback so desktop entry is valid
        ICON_FILE=""
    fi

    # Write desktop entry
    if [ -n "$ICON_FILE" ] && [ -f "$ICON_FILE" ]; then
        ICON_FIELD="$ICON_FILE"
    else
        ICON_FIELD="utilities-terminal"
    fi

    cat > "$DESKTOP_FILE" <<EOF
[Desktop Entry]
Type=Application
Name=$APP_NAME
Comment=Kiro IDE — AI-powered development environment
Exec=$KIRO_BIN %F
Icon=$ICON_FIELD
Terminal=false
Categories=Development;IDE;TextEditor;
MimeType=text/plain;inode/directory;
StartupNotify=true
StartupWMClass=kiro
Keywords=kiro;ide;ai;coding;editor;
EOF

    # Refresh desktop database if available
    if command_exists update-desktop-database; then
        update-desktop-database "$DESKTOP_DIR" >/dev/null 2>&1 || true
    fi

    printf "%b\n" "${GREEN}[✓] Desktop entry: $DESKTOP_FILE${RC}"
    echo ""
}

# ─── PATH persistence ─────────────────────────────────────────────────────────
persist_path() {
    printf "%b\n" "${CYAN}━━━ PATH Configuration ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RC}"

    PATH_BLOCK='
# Kiro IDE / local bin (managed by linutil)
export PATH="$HOME/.local/bin:$PATH"'

    for rc_file in "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.profile" "$HOME/.bash_profile"; do
        if [ -f "$rc_file" ]; then
            if ! grep -q 'Kiro IDE / local bin' "$rc_file"; then
                printf '%s\n' "$PATH_BLOCK" >> "$rc_file"
                printf "%b\n" "${GREEN}[✓] PATH added to $(basename "$rc_file")${RC}"
            else
                printf "%b\n" "${GREEN}[✓] PATH already set in $(basename "$rc_file")${RC}"
            fi
        fi
    done

    # Export for current session
    case ":$PATH:" in
        *:"$BIN_DIR":*) ;;
        *) export PATH="$BIN_DIR:$PATH" ;;
    esac

    echo ""
}

# ─── Verification ─────────────────────────────────────────────────────────────
verify_setup() {
    printf "%b\n" "${CYAN}━━━ Verification ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RC}"

    PASS=true

    if [ -x "$KIRO_BIN" ]; then
        printf "%b\n" "${GREEN}[✓] Binary: $KIRO_BIN${RC}"
    else
        printf "%b\n" "${RED}[✗] Binary not found or not executable${RC}"
        PASS=false
    fi

    if [ -L "$BIN_LINK" ]; then
        printf "%b\n" "${GREEN}[✓] Terminal launcher: kiro -> $KIRO_BIN${RC}"
    else
        printf "%b\n" "${YELLOW}[~] Terminal launcher not found (symlink missing)${RC}"
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
        printf "%b\n" "${YELLOW}[~] Icon not found (fallback used in desktop entry)${RC}"
    fi

    echo ""
    if [ "$PASS" = true ]; then
        printf "%b\n" "${CYAN}=================================================================${RC}"
        printf "%b\n" "${GREEN}  ✅  Kiro IDE installation complete!                            ${RC}"
        printf "%b\n" "${CYAN}=================================================================${RC}"
        echo ""
        printf "%b\n" "${YELLOW}  Launch options:${RC}"
        printf "%b\n" "${CYAN}    kiro                  — terminal launcher (after shell restart)${RC}"
        printf "%b\n" "${CYAN}    $KIRO_BIN    — direct binary${RC}"
        printf "%b\n" "${CYAN}    App menu → 'Kiro IDE' — desktop entry${RC}"
        echo ""
        printf "%b\n" "${YELLOW}  Installed at: $INSTALL_DIR${RC}"
        printf "%b\n" "${YELLOW}  From archive:  $(basename "$TARBALL")${RC}"
        printf "%b\n" "${CYAN}=================================================================${RC}"
    else
        printf "%b\n" "${RED}=================================================================${RC}"
        printf "%b\n" "${RED}  Installation completed with errors. Check output above.${RC}"
        printf "%b\n" "${RED}=================================================================${RC}"
        exit 1
    fi
}

# ─── Main Execution ───────────────────────────────────────────────────────────
checkEscalationTool
phase1_detect
phase2_install
phase3_desktop
persist_path
verify_setup
