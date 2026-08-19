#!/bin/sh -e

# Description: Install/update Google Gemini CLI via npm

. ../../../common-script.sh

checkEnv
checkEscalationTool

printf "%b\n" "${CYAN}=================================================================${RC}"
printf "%b\n" "${YELLOW}         Google Gemini CLI — Linux Installer                    ${RC}"
printf "%b\n" "${CYAN}=================================================================${RC}"

if ! command_exists npm; then
    printf "%b\n" "${RED}[✗] npm is not installed!${RC}"
    printf "%b\n" "${YELLOW}    Please install Node.js and npm first before installing Gemini CLI.${RC}"
    exit 1
fi

if command_exists gemini; then
    printf "%b\n" "${GREEN}[✓] Gemini CLI is already installed at: $(command -v gemini)${RC}"
    printf "%b\n" "${YELLOW}    Updating Gemini CLI...${RC}"
else
    printf "%b\n" "${YELLOW}[*] Installing Gemini CLI via npm...${RC}"
fi

# Run npm install globally. Using --no-progress to prevent linutil UI flooding.
if [ -n "$ESCALATION_TOOL" ] && [ ! -w "$(npm config get prefix)/bin" ]; then
    "$ESCALATION_TOOL" npm install -g @google/gemini-cli --no-progress --no-fund --no-audit
else
    npm install -g @google/gemini-cli --no-progress --no-fund --no-audit
fi

if command_exists gemini; then
    printf "%b\n" "${GREEN}[✓] Gemini CLI successfully installed/updated!${RC}"
    printf "%b\n" "${CYAN}    Run 'gemini' to get started.${RC}"
else
    printf "%b\n" "${YELLOW}[~] Installation finished, but 'gemini' is not in PATH.${RC}"
    printf "%b\n" "${CYAN}    You may need to restart your terminal or add npm global bin to your PATH manually.${RC}"
fi

echo ""
