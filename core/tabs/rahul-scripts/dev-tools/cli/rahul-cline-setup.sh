#!/bin/sh -e

# Description: Install/update Cline via npm

. ../../../common-script.sh

checkEnv
checkEscalationTool

printf "%b\n" "${CYAN}=================================================================${RC}"
printf "%b\n" "${YELLOW}         Cline (NPM) — Linux Installer                          ${RC}"
printf "%b\n" "${CYAN}=================================================================${RC}"

if ! command_exists npm; then
    printf "%b\n" "${RED}[✗] npm is not installed!${RC}"
    printf "%b\n" "${YELLOW}    Please install Node.js and npm first before installing Cline.${RC}"
    exit 1
fi

if command_exists cline; then
    printf "%b\n" "${GREEN}[✓] Cline is already installed at: $(command -v cline)${RC}"
    printf "%b\n" "${YELLOW}    Updating Cline...${RC}"
else
    printf "%b\n" "${YELLOW}[*] Installing Cline via npm...${RC}"
fi

# Run npm install globally. Using --no-progress to prevent linutil UI flooding.
if [ -n "$ESCALATION_TOOL" ] && [ ! -w "$(npm config get prefix)/bin" ]; then
    "$ESCALATION_TOOL" npm install -g cline --no-progress --no-fund --no-audit
else
    npm install -g cline --no-progress --no-fund --no-audit
fi

if command_exists cline; then
    printf "%b\n" "${GREEN}[✓] Cline successfully installed/updated!${RC}"
    printf "%b\n" "${CYAN}    Run 'cline' to get started.${RC}"
else
    printf "%b\n" "${YELLOW}[~] Installation finished, but 'cline' is not in PATH.${RC}"
    printf "%b\n" "${CYAN}    You may need to restart your terminal or add npm global bin to your PATH manually.${RC}"
fi

echo ""
