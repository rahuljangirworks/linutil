#!/bin/sh -e

# Description: Install/update Cursor CLI (Cursor Agent) via official script

. ../../../common-script.sh

checkEnv
checkEscalationTool

printf "%b\n" "${CYAN}=================================================================${RC}"
printf "%b\n" "${YELLOW}         Cursor Agent (CLI) — Linux Installer                   ${RC}"
printf "%b\n" "${CYAN}=================================================================${RC}"

if command_exists cursor-agent; then
    printf "%b\n" "${GREEN}[✓] Cursor Agent is already installed at: $(command -v cursor-agent)${RC}"
    printf "%b\n" "${YELLOW}    Updating Cursor Agent...${RC}"
else
    printf "%b\n" "${YELLOW}[*] Installing Cursor Agent...${RC}"
fi

# Download the script, remove the --progress-bar flag to fix linutil UI flooding, and execute
curl -fsSL https://cursor.com/install | sed 's/--progress-bar/-s/g' | bash

if command_exists cursor-agent; then
    printf "%b\n" "${GREEN}[✓] Cursor Agent successfully installed!${RC}"
    printf "%b\n" "${CYAN}    Run 'agent' or 'cursor-agent' to get started.${RC}"
else
    printf "%b\n" "${YELLOW}[~] Installation finished, but 'cursor-agent' is not in PATH.${RC}"
    printf "%b\n" "${CYAN}    You may need to restart your terminal or add it to your PATH manually.${RC}"
fi

echo ""
