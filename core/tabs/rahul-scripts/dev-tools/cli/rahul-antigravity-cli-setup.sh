#!/bin/sh -e

# Description: Install/update Antigravity CLI via official script

. ../../../common-script.sh

checkEnv
checkEscalationTool

printf "%b\n" "${CYAN}=================================================================${RC}"
printf "%b\n" "${YELLOW}         Antigravity CLI — Linux Installer                      ${RC}"
printf "%b\n" "${CYAN}=================================================================${RC}"

if command_exists agy; then
    printf "%b\n" "${GREEN}[✓] Antigravity CLI is already installed at: $(command -v agy)${RC}"
    printf "%b\n" "${YELLOW}    Updating Antigravity CLI...${RC}"
else
    printf "%b\n" "${YELLOW}[*] Installing Antigravity CLI...${RC}"
fi

curl -fsSL https://antigravity.google/cli/install.sh | bash

if command_exists agy; then
    printf "%b\n" "${GREEN}[✓] Antigravity CLI successfully installed!${RC}"
    printf "%b\n" "${CYAN}    Run 'agy' to get started.${RC}"
else
    printf "%b\n" "${YELLOW}[~] Installation finished, but 'agy' is not in PATH.${RC}"
    printf "%b\n" "${CYAN}    You may need to restart your terminal or add it to your PATH manually.${RC}"
fi

echo ""
