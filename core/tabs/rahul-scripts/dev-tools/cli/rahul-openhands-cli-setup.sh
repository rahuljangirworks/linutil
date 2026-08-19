#!/bin/sh -e

# Description: Install/update OpenHands CLI via uv

. ../../../common-script.sh

checkEnv
checkEscalationTool

printf "%b\n" "${CYAN}=================================================================${RC}"
printf "%b\n" "${YELLOW}         OpenHands CLI — Linux Installer                        ${RC}"
printf "%b\n" "${CYAN}=================================================================${RC}"

if ! command_exists uv; then
    printf "%b\n" "${RED}[✗] 'uv' (Python package manager) is not installed!${RC}"
    printf "%b\n" "${YELLOW}    OpenHands requires uv. Install it via:${RC}"
    printf "%b\n" "${CYAN}    curl -LsSf https://astral.sh/uv/install.sh | sh${RC}"
    exit 1
fi

if command_exists openhands; then
    printf "%b\n" "${GREEN}[✓] OpenHands CLI is already installed at: $(command -v openhands)${RC}"
    printf "%b\n" "${YELLOW}    Updating OpenHands CLI...${RC}"
else
    printf "%b\n" "${YELLOW}[*] Installing OpenHands CLI via uv...${RC}"
fi

# Install/update openhands using uv
uv tool install openhands --python 3.12 --force

if command_exists openhands; then
    printf "%b\n" "${GREEN}[✓] OpenHands CLI successfully installed/updated!${RC}"
    printf "%b\n" "${CYAN}    Run 'openhands' to get started.${RC}"
else
    printf "%b\n" "${RED}[✗] Installation finished, but 'openhands' is not in PATH.${RC}"
    printf "%b\n" "${CYAN}    Ensure ~/.local/bin is in your PATH.${RC}"
    exit 1
fi

echo ""
