#!/bin/sh -e

# Description: Install/update OpenCode AI CLI via official script

. ../../../common-script.sh

checkEnv
checkEscalationTool

printf "%b\n" "${CYAN}=================================================================${RC}"
printf "%b\n" "${YELLOW}         OpenCode AI CLI — Linux Installer                      ${RC}"
printf "%b\n" "${CYAN}=================================================================${RC}"

if command_exists opencode; then
    printf "%b\n" "${GREEN}[✓] OpenCode AI CLI is already installed at: $(command -v opencode)${RC}"
    printf "%b\n" "${YELLOW}    Updating OpenCode AI CLI...${RC}"
else
    printf "%b\n" "${YELLOW}[*] Installing OpenCode AI CLI...${RC}"
fi

# Download the script, remove the --progress-bar flag to fix linutil UI flooding, and execute
curl -fsSL https://opencode.ai/install | sed 's/--progress-bar/-s/g' | bash

if command_exists opencode; then
    printf "%b\n" "${GREEN}[✓] OpenCode AI CLI successfully installed!${RC}"
    printf "%b\n" "${CYAN}    Run 'opencode' to get started.${RC}"
else
    printf "%b\n" "${YELLOW}[~] Installation finished, but 'opencode' is not in PATH.${RC}"
    printf "%b\n" "${CYAN}    You may need to restart your terminal or add it to your PATH manually.${RC}"
fi

echo ""
