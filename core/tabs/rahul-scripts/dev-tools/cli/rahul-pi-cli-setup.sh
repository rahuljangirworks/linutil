#!/bin/sh -e

# Description: Install/update Pi AI CLI via official script

. ../../../common-script.sh

checkEnv
checkEscalationTool

printf "%b\n" "${CYAN}=================================================================${RC}"
printf "%b\n" "${YELLOW}         Pi AI CLI — Linux Installer                            ${RC}"
printf "%b\n" "${CYAN}=================================================================${RC}"

if command_exists pi; then
    printf "%b\n" "${GREEN}[✓] Pi AI CLI is already installed at: $(command -v pi)${RC}"
    printf "%b\n" "${YELLOW}    Updating Pi AI CLI...${RC}"
else
    printf "%b\n" "${YELLOW}[*] Installing Pi AI CLI...${RC}"
fi

# Download the script, remove the --progress-bar flag to fix linutil UI flooding, and execute
curl -fsSL https://pi.dev/install.sh | sed 's/--progress-bar/-s/g' | sh

if command_exists pi; then
    printf "%b\n" "${GREEN}[✓] Pi AI CLI successfully installed!${RC}"
    printf "%b\n" "${CYAN}    Run 'pi' to get started.${RC}"
else
    printf "%b\n" "${YELLOW}[~] Installation finished, but 'pi' is not in PATH.${RC}"
    printf "%b\n" "${CYAN}    You may need to restart your terminal or add it to your PATH manually.${RC}"
fi

echo ""
