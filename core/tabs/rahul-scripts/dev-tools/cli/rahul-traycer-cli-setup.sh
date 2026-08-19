#!/bin/sh -e

# Description: Install/update Traycer AI CLI

. ../../../common-script.sh

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
    printf "%b\n" "${GREEN}[✓] Traycer CLI is already installed at: $(command -v traycer)${RC}"
    printf "%b\n" "${YELLOW}    Updating Traycer CLI...${RC}"
else
    printf "%b\n" "${YELLOW}[*] Installing Traycer CLI via npm...${RC}"
fi

if [ -n "$ESCALATION_TOOL" ] && [ ! -w "$(npm config get prefix)/bin" ]; then
    "$ESCALATION_TOOL" npm install -g @traycerai/cli --no-progress --no-fund --no-audit
else
    npm install -g @traycerai/cli --no-progress --no-fund --no-audit
fi

if command_exists traycer; then
    printf "%b\n" "${GREEN}[✓] Traycer CLI successfully installed/updated!${RC}"
    printf "%b\n" "${CYAN}    Run 'traycer' to get started.${RC}"
else
    printf "%b\n" "${YELLOW}[~] Traycer CLI installed, but 'traycer' is not in PATH.${RC}"
fi
echo ""
