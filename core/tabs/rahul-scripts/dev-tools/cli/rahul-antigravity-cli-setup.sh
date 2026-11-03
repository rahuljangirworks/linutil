#!/bin/sh -e

# Description: Install, update, or remove Antigravity CLI via official script

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
IDE_SCRIPT="$SCRIPT_DIR/../ide/rahul-antigravity-setup.sh"

if [ -x "$IDE_SCRIPT" ]; then
    exec "$IDE_SCRIPT" --cli "$@"
fi

. ../../../common-script.sh
checkEnv

BIN_DIR="$HOME/.local/bin"

if [ -x "/usr/bin/rm" ]; then
    RM_CMD="/usr/bin/rm"
elif [ -x "/bin/rm" ]; then
    RM_CMD="/bin/rm"
else
    RM_CMD="rm"
fi

clean_shell_env() {
    for rc in "$HOME/.bashrc" "$HOME/.bash_profile" "$HOME/.profile" "$HOME/.zshrc"; do
        if [ -f "$rc" ]; then
            sed -i '/# Added by Antigravity CLI installer/{n;d}' "$rc" 2>/dev/null || true
            sed -i '/# Added by Antigravity CLI installer/d' "$rc" 2>/dev/null || true
        fi
    done
}

do_install() {
    printf "%b\n" "${CYAN}=================================================================${RC}"
    printf "%b\n" "${YELLOW}         Antigravity CLI — Linux Installer                      ${RC}"
    printf "%b\n" "${CYAN}=================================================================${RC}"

    pkill -f 'agy ' 2>/dev/null || true
    "$RM_CMD" -f "$BIN_DIR/agy"

    curl -fsSL https://antigravity.google/cli/install.sh | bash

    if command_exists agy; then
        printf "%b\n" "${GREEN}[✓] Antigravity CLI successfully installed at: $(command -v agy)${RC}"
        printf "%b\n" "${CYAN}    Run 'agy' to get started.${RC}"
    elif [ -x "$BIN_DIR/agy" ]; then
        printf "%b\n" "${GREEN}[✓] Antigravity CLI installed in $BIN_DIR/agy${RC}"
        printf "%b\n" "${CYAN}    Run 'agy' to get started (ensure ~/.local/bin is in PATH).${RC}"
    else
        printf "%b\n" "${YELLOW}[~] Installation finished. Ensure ~/.local/bin is in PATH.${RC}"
    fi
    echo ""
}

do_uninstall() {
    printf "%b\n" "${CYAN}=================================================================${RC}"
    printf "%b\n" "${YELLOW}         Antigravity CLI — Linux Uninstaller                    ${RC}"
    printf "%b\n" "${CYAN}=================================================================${RC}"

    pkill -f 'agy ' 2>/dev/null || true
    "$RM_CMD" -f "$BIN_DIR/agy"
    "$RM_CMD" -f "/usr/local/bin/agy" 2>/dev/null || true
    clean_shell_env

    hash -d agy 2>/dev/null || true
    hash -r 2>/dev/null || true

    echo ""
    printf "%b\n" "${GREEN}[✓] Antigravity CLI successfully removed.${RC}"
    printf "%b\n" "${CYAN}-----------------------------------------------------------------${RC}"
    printf "%b\n" "${YELLOW}[!] Shell Command Cache Notice:${RC}"
    printf "%b\n" "${CYAN}    If you ran 'agy' previously in this open terminal session,   ${RC}"
    printf "%b\n" "${CYAN}    Bash remembers command locations in its internal hash table. ${RC}"
    printf "%b\n" "${CYAN}    To clear the cached location immediately in this terminal:   ${RC}"
    printf "%b\n" "${GREEN}      hash -d agy${RC}"
    printf "%b\n" "${CYAN}    Or simply open a new terminal window / tab.                  ${RC}"
    printf "%b\n" "${CYAN}-----------------------------------------------------------------${RC}"
    echo ""
}

case "${1:-}" in
    --uninstall|--remove)
        do_uninstall
        ;;
    --install|--update)
        do_install
        ;;
    *)
        if command_exists agy || [ -x "$BIN_DIR/agy" ]; then
            printf "%b\n" "${CYAN}=================================================================${RC}"
            printf "%b\n" "${YELLOW}         Antigravity CLI Manager                                 ${RC}"
            printf "%b\n" "${CYAN}=================================================================${RC}"
            printf "%b\n" "${GREEN}Antigravity CLI is currently installed: $(command -v agy 2>/dev/null || echo "$BIN_DIR/agy")${RC}"
            printf "%b\n" "${YELLOW}  1) Reinstall / Update CLI${RC}"
            printf "%b\n" "${RED}  2) Uninstall / Remove CLI${RC}"
            printf "%b\n" "${CYAN}  3) Abort${RC}"
            printf "%b\n" "${CYAN}=================================================================${RC}"
            printf "%b" "${YELLOW}Choose an option [1-3, default 1]: ${RC}"
            read -r CHOICE
            CHOICE="${CHOICE:-1}"
            case "$CHOICE" in
                1) do_install ;;
                2) do_uninstall ;;
                3) printf "%b\n" "${YELLOW}Aborted.${RC}"; exit 0 ;;
                *) printf "%b\n" "${RED}Invalid choice.${RC}"; exit 1 ;;
            esac
        else
            do_install
        fi
        ;;
esac
