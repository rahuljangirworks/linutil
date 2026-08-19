#!/bin/sh -e

# Description: Install/update Kilo AI CLI via official script

. ../../../common-script.sh

checkEnv
checkEscalationTool

printf "%b\n" "${CYAN}=================================================================${RC}"
printf "%b\n" "${YELLOW}         Kilo AI CLI — Linux Installer                          ${RC}"
printf "%b\n" "${CYAN}=================================================================${RC}"

if command_exists kilo; then
    printf "%b\n" "${GREEN}[✓] Kilo AI CLI is already installed at: $(command -v kilo)${RC}"
    printf "%b\n" "${YELLOW}    Updating Kilo AI CLI...${RC}"
else
    printf "%b\n" "${YELLOW}[*] Installing Kilo AI CLI...${RC}"
fi

# Download the script, remove the --progress-bar flag to fix linutil UI flooding, and execute
curl -fsSL https://kilo.ai/cli/install | sed 's/--progress-bar/-s/g' | bash

if command_exists kilo; then
    printf "%b\n" "${GREEN}[✓] Kilo AI CLI successfully installed!${RC}"
    printf "%b\n" "${CYAN}    Run 'kilo' to get started.${RC}"
else
    printf "%b\n" "${YELLOW}[~] Installation finished, but 'kilo' is not in PATH.${RC}"
    printf "%b\n" "${CYAN}    You may need to restart your terminal or add it to your PATH manually.${RC}"
fi

echo ""
