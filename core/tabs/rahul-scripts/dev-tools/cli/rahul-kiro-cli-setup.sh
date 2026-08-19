#!/bin/sh -e

# Description: Install/update Kiro CLI via the official installation script

. ../../../common-script.sh

checkEnv
checkEscalationTool

printf "%b\n" "${CYAN}=================================================================${RC}"
printf "%b\n" "${YELLOW}         Kiro CLI — Linux Installer                             ${RC}"
printf "%b\n" "${CYAN}=================================================================${RC}"

if command_exists kiro; then
    printf "%b\n" "${GREEN}[✓] Kiro CLI is already installed at: $(command -v kiro)${RC}"
    printf "%b\n" "${YELLOW}    Updating Kiro CLI...${RC}"
else
    printf "%b\n" "${YELLOW}[*] Installing Kiro CLI...${RC}"
fi

curl -fsSL https://cli.kiro.dev/install | bash

if command_exists kiro; then
    printf "%b\n" "${GREEN}[✓] Kiro CLI successfully installed!${RC}"
    printf "%b\n" "${CYAN}    Run 'kiro' to get started.${RC}"
else
    printf "%b\n" "${YELLOW}[~] Installation finished, but 'kiro' is not in PATH.${RC}"
    printf "%b\n" "${CYAN}    You may need to restart your terminal or add it to your PATH manually.${RC}"
fi

echo ""
