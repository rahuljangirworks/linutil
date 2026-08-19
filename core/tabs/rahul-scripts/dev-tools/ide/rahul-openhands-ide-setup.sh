#!/bin/sh -e

# Description: Setup OpenHands Web UI as a Desktop App

. ../../../common-script.sh

checkEnv

APP_NAME="OpenHands"
DESKTOP_DIR="$HOME/.local/share/applications"
DESKTOP_FILE="$DESKTOP_DIR/openhands.desktop"

printf "%b\n" "${CYAN}=================================================================${RC}"
printf "%b\n" "${YELLOW}         OpenHands Desktop UI — Linux Setup                     ${RC}"
printf "%b\n" "${CYAN}=================================================================${RC}"

if ! command_exists openhands; then
    printf "%b\n" "${RED}[✗] 'openhands' CLI is not installed!${RC}"
    printf "%b\n" "${YELLOW}    Please install the OpenHands CLI first (Dev Tools - CLI -> OpenHands CLI).${RC}"
    exit 1
fi

printf "%b\n" "${YELLOW}[*] Setting up Desktop Entry for OpenHands Web UI...${RC}"
mkdir -p "$DESKTOP_DIR"
cat > "$DESKTOP_FILE" <<EOF
[Desktop Entry]
Type=Application
Name=$APP_NAME
Comment=Open-source AI Software Engineer
Exec=sh -c "$HOME/.local/bin/openhands serve & sleep 2 && xdg-open http://localhost:3000"
Icon=utilities-terminal
Terminal=true
Categories=Development;IDE;
StartupNotify=true
EOF

if command_exists update-desktop-database; then
    update-desktop-database "$DESKTOP_DIR" >/dev/null 2>&1 || true
fi

printf "%b\n" "${GREEN}[✓] Desktop entry created: $DESKTOP_FILE${RC}"
echo ""
printf "%b\n" "${GREEN}=================================================================${RC}"
printf "%b\n" "${GREEN}  ✅  OpenHands Desktop setup complete!                          ${RC}"
printf "%b\n" "${CYAN}=================================================================${RC}"
printf "%b\n" "${YELLOW}  Launch options:${RC}"
printf "%b\n" "${CYAN}    App menu → 'OpenHands'     — Launches UI in your web browser${RC}"
echo ""
