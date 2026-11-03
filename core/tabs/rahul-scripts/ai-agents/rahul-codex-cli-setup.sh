#!/bin/sh -e

# Description: Install/update OpenAI Codex CLI (@openai/codex) via npm

. ../../common-script.sh

checkEnv
checkEscalationTool

printf "%b\n" "${CYAN}=================================================================${RC}"
printf "%b\n" "${YELLOW}         OpenAI Codex CLI — Linux Installer                      ${RC}"
printf "%b\n" "${CYAN}=================================================================${RC}"

if ! command_exists npm; then
    printf "%b\n" "${RED}[✗] npm is not installed!${RC}"
    printf "%b\n" "${YELLOW}    Please install Node.js and npm first before installing Codex CLI.${RC}"
    exit 1
fi

if command_exists codex; then
    printf "%b\n" "${GREEN}[✓] OpenAI Codex CLI is already installed at: $(command -v codex)${RC}"
    printf "%b\n" "${YELLOW}    Updating Codex CLI to the latest version...${RC}"
else
    printf "%b\n" "${YELLOW}[*] Installing OpenAI Codex CLI (@openai/codex) via npm...${RC}"
fi

# Run npm install globally. Using --no-progress to prevent linutil UI flooding.
if [ -n "$ESCALATION_TOOL" ] && [ ! -w "$(npm config get prefix 2>/dev/null || echo '/usr')/bin" ]; then
    "$ESCALATION_TOOL" npm install -g @openai/codex --no-progress --no-fund --no-audit
else
    npm install -g @openai/codex --no-progress --no-fund --no-audit
fi

if command_exists codex; then
    printf "%b\n" "${GREEN}[✓] OpenAI Codex CLI successfully installed/updated!${RC}"
    printf "%b\n" "${CYAN}    Run 'codex' in your terminal to start.${RC}"
else
    printf "%b\n" "${YELLOW}[~] Installation finished, but 'codex' is not yet in PATH.${RC}"
    printf "%b\n" "${CYAN}    Ensure your npm global bin directory is in your PATH, or restart your shell.${RC}"
fi

echo ""
