#!/bin/sh -e

# Description: Install/update Traycer AI CLI (@traycerai/cli)
# Homepage:    https://traycer.ai
# Source:      https://github.com/traycerai/traycer

case "$0" in
    */*) script_path="$0" ;;
    *) script_path="$(command -v -- "$0" 2>/dev/null || printf "%s\n" "$0")" ;;
esac
SCRIPT_DIR="$(dirname "$script_path")"
SCRIPT_DIR="$(cd "$SCRIPT_DIR" && pwd)"
unset script_path

if [ -f "$SCRIPT_DIR/../../common-script.sh" ]; then
    . "$SCRIPT_DIR/../../common-script.sh"
elif [ -f "../../common-script.sh" ]; then
    . ../../common-script.sh
else
    RC='\033[0m'
    RED='\033[31m'
    YELLOW='\033[33m'
    CYAN='\033[36m'
    GREEN='\033[32m'
fi

checkEnv
checkEscalationTool

printf "%b\n" "${CYAN}=================================================================${RC}"
printf "%b\n" "${YELLOW}         Traycer AI CLI — Linux Installer                       ${RC}"
printf "%b\n" "${CYAN}=================================================================${RC}"

if ! command_exists npm; then
    printf "%b\n" "${RED}[✗] npm is not installed! Cannot install CLI.${RC}"
    printf "%b\n" "${YELLOW}    Please install Node.js and npm first.${RC}"
    exit 1
fi

if command_exists traycer; then
    cli_ver=$(traycer --version 2>/dev/null || echo "installed")
    printf "%b\n" "${GREEN}[✓] Traycer CLI is already installed: $cli_ver ($(command -v traycer))${RC}"
    printf "%b\n" "${YELLOW}    Updating Traycer CLI to latest version...${RC}"
else
    printf "%b\n" "${YELLOW}[*] Installing Traycer CLI (@traycerai/cli) via npm...${RC}"
fi

npm_prefix=$(npm config get prefix 2>/dev/null || echo "/usr/local")
if [ -n "$ESCALATION_TOOL" ] && [ ! -w "$npm_prefix/bin" ]; then
    "$ESCALATION_TOOL" npm install -g @traycerai/cli --no-progress --no-fund --no-audit || npm install -g @traycerai/cli --no-progress --no-fund --no-audit
else
    npm install -g @traycerai/cli --no-progress --no-fund --no-audit
fi

if command_exists traycer; then
    printf "%b\n" "${GREEN}[✓] Traycer CLI successfully installed/updated!${RC}"
    printf "%b\n" "${CYAN}    Run 'traycer' or 'traycer --help' to get started.${RC}"
else
    printf "%b\n" "${YELLOW}[~] Traycer CLI installed, but 'traycer' is not currently in PATH.${RC}"
    printf "%b\n" "${CYAN}    Ensure '$npm_prefix/bin' is added to your PATH.${RC}"
fi
echo ""
