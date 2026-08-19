#!/bin/sh -e

# Description: Install/update Traycer AI Desktop AppImage

. ../../../common-script.sh

checkEnv

APP_NAME="Traycer AI"
APPIMAGE_PATH="$HOME/.local/bin/Traycer.AppImage"
DESKTOP_DIR="$HOME/.local/share/applications"
DESKTOP_FILE="$DESKTOP_DIR/traycer.desktop"

printf "%b\n" "${CYAN}=================================================================${RC}"
printf "%b\n" "${YELLOW}         Traycer AI Desktop — Linux Installer                   ${RC}"
printf "%b\n" "${CYAN}=================================================================${RC}"

mkdir -p "$HOME/.local/bin"

printf "%b\n" "${YELLOW}[*] Fetching latest release info from GitHub...${RC}"
LATEST_URL=$(curl -s https://api.github.com/repos/traycerai/traycer/releases/latest | grep "browser_download_url" | grep "AppImage" | cut -d '"' -f 4 | head -1)

if [ -z "$LATEST_URL" ]; then
    printf "%b\n" "${RED}[✗] Could not find the latest AppImage URL. You may need to install it manually.${RC}"
    exit 1
fi

printf "%b\n" "${YELLOW}[*] Downloading Desktop AppImage...${RC}"
printf "%b\n" "${CYAN}    URL: $LATEST_URL${RC}"
curl -fsSL "$LATEST_URL" -o "$APPIMAGE_PATH" || {
    printf "%b\n" "${RED}[✗] Download failed.${RC}"
    exit 1
}

chmod +x "$APPIMAGE_PATH"
printf "%b\n" "${GREEN}[✓] AppImage installed to: $APPIMAGE_PATH${RC}"

printf "%b\n" "${YELLOW}[*] Patching Traycer config directory (prevents startup crash)...${RC}"
mkdir -p "$HOME/.config/Traycer/logs"

printf "%b\n" "${YELLOW}[*] Creating Desktop Entry...${RC}"
mkdir -p "$DESKTOP_DIR"
cat > "$DESKTOP_FILE" <<EOF
[Desktop Entry]
Type=Application
Name=$APP_NAME
Comment=Traycer AI Agent Platform
Exec=$APPIMAGE_PATH --appimage-extract-and-run %U
Icon=utilities-terminal
Terminal=false
Categories=Development;IDE;
StartupNotify=true
EOF

if command_exists update-desktop-database; then
    update-desktop-database "$DESKTOP_DIR" >/dev/null 2>&1 || true
fi
printf "%b\n" "${GREEN}[✓] Desktop entry created: $DESKTOP_FILE${RC}"

echo ""
printf "%b\n" "${GREEN}=================================================================${RC}"
printf "%b\n" "${GREEN}  ✅  Traycer AI Desktop setup complete!                         ${RC}"
printf "%b\n" "${CYAN}=================================================================${RC}"
printf "%b\n" "${YELLOW}  Launch options:${RC}"
printf "%b\n" "${CYAN}    App menu → 'Traycer AI'    — Launches the Desktop App${RC}"
echo ""
