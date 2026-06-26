#!/bin/sh -e

# Description: Update a Linutil installation made through cargo.

. ../../common-script.sh

ensureCargo() {
    if command_exists cargo; then
        return 0
    fi

    printf "%b\n" "${YELLOW}Installing Rust toolchain...${RC}"
    case "$PACKAGER" in
        pacman)
            "$ESCALATION_TOOL" "$PACKAGER" -S --needed --noconfirm rustup
            ;;
        dnf)
            "$ESCALATION_TOOL" "$PACKAGER" install -y curl rustup man-pages man-db man
            rustup-init -y
            ;;
        zypper)
            "$ESCALATION_TOOL" "$PACKAGER" install -n curl gcc make rustup
            ;;
        apk)
            "$ESCALATION_TOOL" "$PACKAGER" add build-base rustup
            rustup-init -y
            ;;
        *)
            curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
            ;;
    esac

    if [ -f "$HOME/.cargo/env" ]; then
        # shellcheck disable=SC1091
        . "$HOME/.cargo/env"
    else
        export PATH="$HOME/.cargo/bin:$PATH"
    fi
}

updateLinutil() {
    if [ ! -e "$HOME/.cargo/bin/linutil" ]; then
        printf "%b\n" "${RED}This script only updates the binary installed through cargo.${RC}"
        printf "%b\n" "${RED}linutil_tui is not installed at ~/.cargo/bin/linutil.${RC}"
        exit 1
    fi

    ensureCargo
    rustup default stable

    installed_version=$(cargo install --list | awk '/^linutil_tui / {gsub(/[v:]/, "", $2); print $2; exit}')
    latest_version=$(curl -fsSL https://crates.io/api/v1/crates/linutil_tui |
        sed -n 's/.*"max_version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')

    if [ -z "$latest_version" ]; then
        printf "%b\n" "${RED}Could not determine the latest linutil_tui version.${RC}"
        exit 1
    fi

    if [ "$installed_version" = "$latest_version" ]; then
        printf "%b\n" "${GREEN}linutil_tui is up to date.${RC}"
        exit 0
    fi

    printf "%b\n" "${YELLOW}Updating linutil_tui...${RC}"
    cargo install --force linutil_tui
    printf "%b\n" "${GREEN}Updated successfully.${RC}"
}

checkEnv
updateLinutil
