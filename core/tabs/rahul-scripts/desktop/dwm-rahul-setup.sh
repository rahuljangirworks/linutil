#!/bin/sh -e

# Description: Install/update dwm-rahul through the fork's own installer.
# Repository: https://github.com/rahuljangirworks/dwm-rahul

. ../../common-script.sh

DWM_REPO_URL="https://github.com/rahuljangirworks/dwm-rahul.git"
DWM_REPO_SSH_URL="git@github.com:rahuljangirworks/dwm-rahul.git"
DWM_BRANCH="${DWM_BRANCH:-main}"
DWM_DIR="${DWM_RAHUL_DIR:-$HOME/.local/share/dwm-rahul}"
DWM_INSTALL_PROFILE="${DWM_INSTALL_PROFILE:-full}"

ensureGit() {
    if command_exists git; then
        return 0
    fi

    printf "%b\n" "${YELLOW}Installing git so dwm-rahul can be cloned...${RC}"
    case "$PACKAGER" in
        pacman)
            "$ESCALATION_TOOL" "$PACKAGER" -S --needed --noconfirm git
            ;;
        apt-get | nala | dnf | zypper)
            "$ESCALATION_TOOL" "$PACKAGER" install -y git
            ;;
        apk)
            "$ESCALATION_TOOL" "$PACKAGER" add git
            ;;
        xbps-install)
            "$ESCALATION_TOOL" "$PACKAGER" -Sy git
            ;;
        eopkg)
            "$ESCALATION_TOOL" "$PACKAGER" install -y git
            ;;
        *)
            printf "%b\n" "${RED}Unsupported package manager: $PACKAGER${RC}"
            return 1
            ;;
    esac
}

ensureDwmRepo() {
    parent_dir=$(dirname "$DWM_DIR")
    [ ! -d "$parent_dir" ] && mkdir -p "$parent_dir"

    if [ -d "$DWM_DIR" ] && [ ! -d "$DWM_DIR/.git" ]; then
        printf "%b\n" "${RED}$DWM_DIR exists but is not a git repository.${RC}"
        printf "%b\n" "${YELLOW}Move it aside or set DWM_RAHUL_DIR to another path.${RC}"
        return 1
    fi

    if [ ! -d "$DWM_DIR/.git" ]; then
        printf "%b\n" "${YELLOW}Cloning dwm-rahul...${RC}"
        git clone --branch "$DWM_BRANCH" "$DWM_REPO_URL" "$DWM_DIR"
        return 0
    fi

    origin_url=$(git -C "$DWM_DIR" remote get-url origin 2>/dev/null || true)
    case "$origin_url" in
        "$DWM_REPO_URL" | "$DWM_REPO_SSH_URL" | "https://github.com/rahuljangirworks/dwm-rahul")
            ;;
        *)
            printf "%b\n" "${RED}$DWM_DIR origin is not Rahul's dwm fork.${RC}"
            printf "%b\n" "${YELLOW}Expected: $DWM_REPO_URL${RC}"
            printf "%b\n" "${YELLOW}Found:    ${origin_url:-missing}${RC}"
            return 1
            ;;
    esac

    if [ -n "$(git -C "$DWM_DIR" status --short)" ]; then
        printf "%b\n" "${RED}$DWM_DIR has local changes.${RC}"
        printf "%b\n" "${YELLOW}Commit, stash, or clean them before updating from origin.${RC}"
        return 1
    fi

    printf "%b\n" "${YELLOW}Fast-forwarding dwm-rahul from origin/$DWM_BRANCH...${RC}"
    git -C "$DWM_DIR" fetch origin "$DWM_BRANCH"
    git -C "$DWM_DIR" checkout "$DWM_BRANCH"
    git -C "$DWM_DIR" merge --ff-only "origin/$DWM_BRANCH"
}

runDwmInstaller() {
    if [ ! -f "$DWM_DIR/install.sh" ]; then
        printf "%b\n" "${RED}Missing $DWM_DIR/install.sh${RC}"
        return 1
    fi

    printf "%b\n" "${YELLOW}Running dwm-rahul installer profile: $DWM_INSTALL_PROFILE${RC}"
    bash "$DWM_DIR/install.sh" --profile "$DWM_INSTALL_PROFILE" --non-interactive --yes
    printf "%b\n" "${GREEN}dwm-rahul installation complete.${RC}"
    printf "%b\n" "${CYAN}Log out and select dwm, or run startx when your setup uses it.${RC}"
}

checkEnv
ensureGit
ensureDwmRepo
runDwmInstaller
