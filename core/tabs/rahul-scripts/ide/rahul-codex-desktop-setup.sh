#!/bin/sh -e

# Description: Install OpenAI Codex Desktop (unofficial Linux AppImage)
# Downloads the latest AppImage from cuongducle/codex-linux, installs icon + desktop entry
# Works on: Arch, Debian, Fedora, openSUSE, Void, Alpine, any Linux with FUSE

. ../../common-script.sh

checkEnv

# ─── Globals ──────────────────────────────────────────────────────────────────
APP_NAME="Codex Desktop"
APPIMAGE_API="https://api.github.com/repos/cuongducle/codex-linux/releases/latest"
INSTALL_DIR="$HOME/.local/share/codex-desktop"
APPIMAGE_PATH="$INSTALL_DIR/codex-desktop.AppImage"
BIN_DIR="$HOME/.local/bin"
BIN_LINK="$BIN_DIR/codex-desktop"
DESKTOP_DIR="$HOME/.local/share/applications"
DESKTOP_FILE="$DESKTOP_DIR/codex-desktop.desktop"
ICON_DIR="$HOME/.local/share/icons/hicolor/256x256/apps"
ICON_FILE="$ICON_DIR/chatgpt-logo.png"
ICON_URL="https://upload.wikimedia.org/wikipedia/commons/thumb/e/ef/ChatGPT-Logo.svg/960px-ChatGPT-Logo.svg.png"

# ─── Header ───────────────────────────────────────────────────────────────────
clear 2>/dev/null || true
printf "%b\n" "${CYAN}=================================================================${RC}"
printf "%b\n" "${YELLOW}         Codex Desktop — Linux Installer (AppImage)             ${RC}"
printf "%b\n" "${CYAN}=================================================================${RC}"
printf "%b\n" "${GREEN}  Phase 1: Install FUSE (required for AppImages)                ${RC}"
printf "%b\n" "${GREEN}  Phase 2: Download AppImage from GitHub release                ${RC}"
printf "%b\n" "${GREEN}  Phase 3: Desktop entry + icon + ~/.local/bin launcher         ${RC}"
printf "%b\n" "${CYAN}=================================================================${RC}"
echo ""

# ─── Phase 1: Ensure FUSE is installed ────────────────────────────────────────
phase1_fuse() {
    printf "%b\n" "${CYAN}━━━ Phase 1: Checking FUSE dependency ━━━━━━━━━━━━━━━━━━━━━━━━${RC}"

    if command_exists fusermount; then
        printf "%b\n" "${GREEN}[✓] FUSE is already installed${RC}"
        return
    fi

    printf "%b\n" "${YELLOW}[*] Installing FUSE (required for AppImages)...${RC}"

    if command_exists pacman; then
        checkEscalationTool
        "$ESCALATION_TOOL" pacman -S --noconfirm fuse2
    elif command_exists apt; then
        checkEscalationTool
        "$ESCALATION_TOOL" apt update && "$ESCALATION_TOOL" apt install -y libfuse2
    elif command_exists dnf; then
        checkEscalationTool
        "$ESCALATION_TOOL" dnf install -y fuse fuse-libs
    elif command_exists apk; then
        checkEscalationTool
        "$ESCALATION_TOOL" apk add fuse fuse-libs
    else
        printf "%b\n" "${YELLOW}[~] Could not auto-install FUSE. Install 'fuse2' manually.${RC}"
        printf "%b\n" "${YELLOW}    AppImage may still work with --appimage-extract.${RC}"
    fi

    echo ""
}

# ─── Phase 2: Download AppImage ──────────────────────────────────────────────
phase2_download() {
    printf "%b\n" "${CYAN}━━━ Phase 2: Downloading Codex Desktop AppImage ━━━━━━━━━━━━━━${RC}"

    mkdir -p "$INSTALL_DIR" "$BIN_DIR" "$DESKTOP_DIR" "$ICON_DIR"

    if [ -f "$APPIMAGE_PATH" ]; then
        printf "%b\n" "${YELLOW}[~] Codex Desktop already installed at $INSTALL_DIR${RC}"
        printf "%b\n" "${YELLOW}    Updating to latest release...${RC}"
        rm -f "$APPIMAGE_PATH"
    fi

    printf "%b\n" "${YELLOW}[*] Resolving latest release from GitHub API...${RC}"
    APPIMAGE_URL=$(curl -fsSL "$APPIMAGE_API" 2>/dev/null | grep "browser_download_url" | grep "AppImage" | grep "amd64" | head -1 | grep -o 'https://[^"]*' || true)

    if [ -z "$APPIMAGE_URL" ]; then
        printf "%b\n" "${RED}[✗] Could not resolve latest release URL from GitHub.${RC}"
        printf "%b\n" "${YELLOW}    Check: https://github.com/cuongducle/codex-linux/releases${RC}"
        exit 1
    fi

    printf "%b\n" "${GREEN}[✓] Found: $(basename "$APPIMAGE_URL")${RC}"
    printf "%b\n" "${YELLOW}[*] Downloading...${RC}"
    if curl -fSL "$APPIMAGE_URL" -o "$APPIMAGE_PATH" 2>/dev/null; then
        chmod +x "$APPIMAGE_PATH"
        printf "%b\n" "${GREEN}[✓] Downloaded and made executable: $APPIMAGE_PATH${RC}"
    else
        printf "%b\n" "${RED}[✗] Download failed. Check your network connection.${RC}"
        printf "%b\n" "${YELLOW}    Manual download:${RC}"
        printf "%b\n" "${CYAN}      $APPIMAGE_URL${RC}"
        printf "%b\n" "${YELLOW}    Save to: $APPIMAGE_PATH${RC}"
        exit 1
    fi

    echo ""
}

# ─── Phase 3: Icon + Desktop Entry + Launcher ────────────────────────────────
phase3_desktop() {
    printf "%b\n" "${CYAN}━━━ Phase 3: Icon & Desktop Entry ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RC}"

    # Download icon
    printf "%b\n" "${YELLOW}[*] Downloading ChatGPT icon...${RC}"
    if curl -fsSL "$ICON_URL" -o "$ICON_FILE" 2>/dev/null; then
        printf "%b\n" "${GREEN}[✓] Icon saved: $ICON_FILE${RC}"
    else
        printf "%b\n" "${YELLOW}[~] Icon download failed. Using fallback.${RC}"
        ICON_FILE=""
    fi

    # Set icon field
    if [ -n "$ICON_FILE" ] && [ -f "$ICON_FILE" ]; then
        ICON_FIELD="$ICON_FILE"
    else
        ICON_FIELD="utilities-terminal"
    fi

    # Write desktop entry
    cat > "$DESKTOP_FILE" <<EOF
[Desktop Entry]
Type=Application
Name=$APP_NAME
Comment=OpenAI Codex Desktop — AI-powered coding agent
Exec=$APPIMAGE_PATH %U
Icon=$ICON_FIELD
Terminal=false
Categories=Development;IDE;
StartupNotify=true
StartupWMClass=codex
Keywords=codex;openai;ai;coding;agent;
EOF

    # Create symlink in ~/.local/bin
    ln -sf "$APPIMAGE_PATH" "$BIN_LINK"

    # Refresh desktop database
    if command_exists update-desktop-database; then
        update-desktop-database "$DESKTOP_DIR" >/dev/null 2>&1 || true
    fi

    printf "%b\n" "${GREEN}[✓] Desktop entry: $DESKTOP_FILE${RC}"
    printf "%b\n" "${GREEN}[✓] Launcher symlink: $BIN_LINK${RC}"
    echo ""
}

# ─── PATH persistence ─────────────────────────────────────────────────────────
persist_path() {
    printf "%b\n" "${CYAN}━━━ PATH Configuration ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RC}"

    PATH_BLOCK='
# Codex Desktop / local bin (managed by linutil)
export PATH="$HOME/.local/bin:$PATH"'

    for rc_file in "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.profile" "$HOME/.bash_profile"; do
        if [ -f "$rc_file" ]; then
            if ! grep -q 'Codex Desktop / local bin' "$rc_file"; then
                printf '%s\n' "$PATH_BLOCK" >> "$rc_file"
                printf "%b\n" "${GREEN}[✓] PATH added to $(basename "$rc_file")${RC}"
            else
                printf "%b\n" "${GREEN}[✓] PATH already set in $(basename "$rc_file")${RC}"
            fi
        fi
    done

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

    if [ -x "$APPIMAGE_PATH" ]; then
        printf "%b\n" "${GREEN}[✓] AppImage: $APPIMAGE_PATH${RC}"
    else
        printf "%b\n" "${RED}[✗] AppImage not found or not executable${RC}"
        PASS=false
    fi

    if [ -L "$BIN_LINK" ]; then
        printf "%b\n" "${GREEN}[✓] Terminal launcher: codex-desktop -> AppImage${RC}"
    else
        printf "%b\n" "${YELLOW}[~] Terminal launcher missing${RC}"
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
        printf "%b\n" "${YELLOW}[~] Icon not found (fallback used)${RC}"
    fi

    echo ""
    if [ "$PASS" = true ]; then
        printf "%b\n" "${CYAN}=================================================================${RC}"
        printf "%b\n" "${GREEN}  ✅  Codex Desktop installation complete!                       ${RC}"
        printf "%b\n" "${CYAN}=================================================================${RC}"
        echo ""
        printf "%b\n" "${YELLOW}  Launch options:${RC}"
        printf "%b\n" "${CYAN}    codex-desktop             — terminal launcher (after rehash)${RC}"
        printf "%b\n" "${CYAN}    $APPIMAGE_PATH  — direct AppImage${RC}"
        printf "%b\n" "${CYAN}    App menu → 'Codex Desktop' — desktop entry${RC}"
        echo ""
        printf "%b\n" "${YELLOW}  Note: You may also need the Codex CLI separately:${RC}"
        printf "%b\n" "${CYAN}    npm i -g @openai/codex   — or use yay -S openai-codex${RC}"
        echo ""
        printf "%b\n" "${YELLOW}  Installed at: $INSTALL_DIR${RC}"
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
phase1_fuse
phase2_download
phase3_desktop
persist_path
verify_setup
