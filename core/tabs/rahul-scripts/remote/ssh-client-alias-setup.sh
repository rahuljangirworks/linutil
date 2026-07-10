#!/bin/sh -e

# Description: Client SSH - configure a client machine to connect to a Rahul hardened SSH server.
# Rerunnable: Yes - validates key, rewrites managed SSH config block, optional shell alias.

. ../../common-script.sh

SSH_DIR="$HOME/.ssh"
SSH_CONFIG="$SSH_DIR/config"
DEFAULT_KEY_FILE="$SSH_DIR/rahul_authorized_keys"
DEFAULT_PORT="2222"
DEFAULT_USER="$(id -un)"
DEFAULT_ALIAS="rahul-server"
PRELOADED_KEY_LINE=""

installSSHClient() {
    if command_exists ssh ssh-keygen; then
        printf "%b\n" "${GREEN}✓ OpenSSH client already installed${RC}"
        return 0
    fi

    printf "%b\n" "${YELLOW}Installing OpenSSH client...${RC}"
    checkEscalationTool
    checkPackageManager 'nala apt-get dnf pacman zypper apk xbps-install eopkg'

    case "$PACKAGER" in
        pacman)
            "$ESCALATION_TOOL" "$PACKAGER" -S --needed --noconfirm openssh
            ;;
        apt-get|nala)
            "$ESCALATION_TOOL" "$PACKAGER" update
            "$ESCALATION_TOOL" "$PACKAGER" install -y openssh-client
            ;;
        dnf|yum)
            "$ESCALATION_TOOL" "$PACKAGER" install -y openssh-clients
            ;;
        zypper)
            "$ESCALATION_TOOL" "$PACKAGER" install -y openssh
            ;;
        apk)
            "$ESCALATION_TOOL" "$PACKAGER" add openssh-client
            ;;
        xbps-install)
            "$ESCALATION_TOOL" "$PACKAGER" -Sy openssh
            ;;
        eopkg)
            "$ESCALATION_TOOL" "$PACKAGER" install -y openssh
            ;;
        *)
            printf "%b\n" "${RED}✗ Unsupported package manager: $PACKAGER${RC}"
            exit 1
            ;;
    esac
}

promptConnectionDetails() {
    printf "%b\n" "${CYAN}========================================${RC}"
    printf "%b\n" "${CYAN}Client SSH Connection Details${RC}"
    printf "%b\n" "${CYAN}========================================${RC}"

    printf "%b" "${YELLOW}Server IP or hostname: ${RC}"
    read -r SERVER_HOST
    if [ -z "$SERVER_HOST" ]; then
        printf "%b\n" "${RED}Server IP/hostname is required.${RC}"
        exit 1
    fi

    printf "%b" "${YELLOW}Server username [${DEFAULT_USER}]: ${RC}"
    read -r SSH_USER
    SSH_USER="${SSH_USER:-$DEFAULT_USER}"

    printf "%b" "${YELLOW}Server SSH port [${DEFAULT_PORT}]: ${RC}"
    read -r SSH_PORT
    SSH_PORT="${SSH_PORT:-$DEFAULT_PORT}"
    case "$SSH_PORT" in
        *[!0-9]*|"")
            printf "%b\n" "${RED}SSH port must be a number.${RC}"
            exit 1
            ;;
    esac

    printf "%b" "${YELLOW}SSH config alias [${DEFAULT_ALIAS}]: ${RC}"
    read -r HOST_ALIAS
    HOST_ALIAS="${HOST_ALIAS:-$DEFAULT_ALIAS}"

    case "$HOST_ALIAS" in
        *[!A-Za-z0-9._-]*|"")
            printf "%b\n" "${RED}Alias can only use letters, numbers, dot, underscore, and dash.${RC}"
            exit 1
            ;;
    esac

    printf "%b" "${YELLOW}Use key file path ${DEFAULT_KEY_FILE}? [Y/n] Do not paste the key here: ${RC}"
    read -r key_path_choice
    case "$key_path_choice" in
        *"-----BEGIN OPENSSH PRIVATE KEY-----"*)
            KEY_FILE="$DEFAULT_KEY_FILE"
            PRELOADED_KEY_LINE="-----BEGIN OPENSSH PRIVATE KEY-----"
            printf "%b\n" "${YELLOW}→ Detected key paste early, using default key path.${RC}"
            ;;
        n|N|no|NO)
            printf "%b" "${YELLOW}Private key path [${DEFAULT_KEY_FILE}]: ${RC}"
            read -r KEY_FILE
            KEY_FILE="${KEY_FILE:-$DEFAULT_KEY_FILE}"
            ;;
        *)
            KEY_FILE="$DEFAULT_KEY_FILE"
            ;;
    esac

    case "$KEY_FILE" in
        -*)
            printf "%b\n" "${RED}Private key path cannot start with '-'.${RC}"
            exit 1
            ;;
        *[[:space:]]*)
            printf "%b\n" "${RED}Private key path cannot contain spaces.${RC}"
            exit 1
            ;;
    esac
}

pastePrivateKey() {
    KEY_TMP=$(mktemp "$SSH_DIR/rahul_authorized_keys.XXXXXX")
    PUB_TMP="${KEY_TMP}.pub"

    printf "%b\n" "${CYAN}Private key input method:${RC}"
    printf "%b\n" "${CYAN}  1. One-line base64 key (recommended for Linutil paste)${RC}"
    printf "%b\n" "${CYAN}  2. Normal OpenSSH private key block${RC}"
    printf "%b" "${YELLOW}Choose method [1] (press Enter for recommended): ${RC}"
    read -r key_input_method
    key_input_method="${key_input_method:-1}"

    case "$key_input_method" in
        1|y|Y|yes|YES)
            pasteBase64PrivateKey "$KEY_TMP" "$PUB_TMP"
            ;;
        2)
            pasteOpenSSHPrivateKey "$KEY_TMP" "$PUB_TMP"
            ;;
        *)
            rm -f "$KEY_TMP" "$PUB_TMP"
            printf "%b\n" "${RED}Invalid key input method.${RC}"
            exit 1
            ;;
    esac
}

hideInput() {
    PASTE_STTY_STATE=""
    if [ -t 0 ]; then
        PASTE_STTY_STATE=$(stty -g 2>/dev/null || true)
        if [ -n "$PASTE_STTY_STATE" ]; then
            stty -echo 2>/dev/null || PASTE_STTY_STATE=""
            trap 'if [ -n "$PASTE_STTY_STATE" ]; then stty "$PASTE_STTY_STATE"; printf "\n"; fi; exit 130' INT TERM HUP
        fi
    fi
}

restoreInput() {
    if [ -n "${PASTE_STTY_STATE:-}" ]; then
        stty "$PASTE_STTY_STATE"
        printf "\n"
        trap - INT TERM HUP
    fi
}

saveValidatedKey() {
    KEY_TMP="$1"
    PUB_TMP="$2"

    chmod 600 "$KEY_TMP"

    if ! ssh-keygen -y -f "$KEY_TMP" > "$PUB_TMP" 2>/dev/null; then
        rm -f "$KEY_TMP" "$PUB_TMP"
        printf "%b\n" "${RED}✗ Invalid private key. Nothing was saved.${RC}"
        exit 1
    fi

    if [ -f "$KEY_FILE" ]; then
        BACKUP_FILE="${KEY_FILE}.$(date '+%Y%m%d_%H%M%S').bak"
        mv "$KEY_FILE" "$BACKUP_FILE"
        printf "%b\n" "${YELLOW}→ Existing key backed up: $BACKUP_FILE${RC}"
    fi

    mv "$KEY_TMP" "$KEY_FILE"
    mv "$PUB_TMP" "${KEY_FILE}.pub"
    chmod 600 "$KEY_FILE"
    chmod 644 "${KEY_FILE}.pub"
    printf "%b\n" "${GREEN}✓ Private key saved: $KEY_FILE${RC}"
}

pasteBase64PrivateKey() {
    KEY_TMP="$1"
    PUB_TMP="$2"

    if ! command_exists base64; then
        rm -f "$KEY_TMP" "$PUB_TMP"
        printf "%b\n" "${RED}base64 command is required for this method.${RC}"
        exit 1
    fi

    printf "%b\n" "${CYAN}On the server, copy the output of:${RC}"
    printf "%b\n" "${YELLOW}  base64 -w0 ~/.ssh/rahul_authorized_keys${RC}"
    printf "%b\n" "${CYAN}Paste that one long line here. Input is hidden.${RC}"

    hideInput
    read -r KEY_B64
    restoreInput

    if [ -z "$KEY_B64" ]; then
        rm -f "$KEY_TMP" "$PUB_TMP"
        printf "%b\n" "${RED}No key data pasted. Nothing was saved.${RC}"
        exit 1
    fi

    if ! printf "%s" "$KEY_B64" | base64 -d > "$KEY_TMP" 2>/dev/null; then
        rm -f "$KEY_TMP" "$PUB_TMP"
        printf "%b\n" "${RED}Invalid base64 key data. Nothing was saved.${RC}"
        exit 1
    fi

    saveValidatedKey "$KEY_TMP" "$PUB_TMP"
}

pasteOpenSSHPrivateKey() {
    KEY_TMP="$1"
    PUB_TMP="$2"

    printf "%b\n" "${CYAN}Paste is hidden, so the key will not be shown on screen.${RC}"
    printf "%b\n" "${CYAN}Start with: -----BEGIN OPENSSH PRIVATE KEY-----${RC}"
    printf "%b\n" "${CYAN}End with:   -----END OPENSSH PRIVATE KEY-----${RC}"
    printf "%b\n" "${CYAN}The script continues automatically after the END line is pasted.${RC}"

    hideInput
    KEY_HAS_END="no"
    if [ -n "$PRELOADED_KEY_LINE" ]; then
        printf "%s\n" "$PRELOADED_KEY_LINE" >> "$KEY_TMP"
    fi

    while IFS= read -r key_line; do
        clean_line=$(printf "%s" "$key_line" | tr -d '\r')
        case "$clean_line" in
            *"-----BEGIN OPENSSH PRIVATE KEY-----"*)
                clean_line="-----BEGIN OPENSSH PRIVATE KEY-----"
                ;;
            *"-----END OPENSSH PRIVATE KEY-----"*)
                clean_line="-----END OPENSSH PRIVATE KEY-----"
                ;;
        esac

        printf "%s\n" "$clean_line" >> "$KEY_TMP"
        if [ "$clean_line" = "-----END OPENSSH PRIVATE KEY-----" ]; then
            KEY_HAS_END="yes"
            break
        fi
    done

    restoreInput

    if [ "$KEY_HAS_END" != "yes" ]; then
        rm -f "$KEY_TMP" "$PUB_TMP"
        printf "%b\n" "${RED}✗ Private key paste was incomplete. Nothing was saved.${RC}"
        exit 1
    fi

    saveValidatedKey "$KEY_TMP" "$PUB_TMP"
}

ensurePrivateKey() {
    mkdir -p "$SSH_DIR"
    chmod 700 "$SSH_DIR"
    KEY_DIR=$(dirname -- "$KEY_FILE")
    mkdir -p "$KEY_DIR"

    if [ -f "$KEY_FILE" ]; then
        if ssh-keygen -y -f "$KEY_FILE" > "${KEY_FILE}.pub" 2>/dev/null; then
            chmod 600 "$KEY_FILE"
            chmod 644 "${KEY_FILE}.pub"
            printf "%b\n" "${GREEN}✓ Existing valid key found: $KEY_FILE${RC}"
            printf "%b" "${YELLOW}Paste/replace private key now? [y/N]: ${RC}"
            read -r replace_existing
            case "$replace_existing" in
                y|Y|yes|YES)
                    pastePrivateKey
                    ;;
                *)
                    printf "%b\n" "${GREEN}✓ Using existing valid key${RC}"
                    ;;
            esac
            return 0
        fi

        printf "%b\n" "${YELLOW}Existing key is invalid. Paste a new private key next.${RC}"
    else
        printf "%b\n" "${YELLOW}No key found at $KEY_FILE. Paste the private key next.${RC}"
    fi

    pastePrivateKey
}

writeSSHConfigAlias() {
    BEGIN_MARKER="# BEGIN rahul ssh client: $HOST_ALIAS"
    END_MARKER="# END rahul ssh client: $HOST_ALIAS"
    TMP_CONFIG=$(mktemp "$SSH_DIR/config.XXXXXX")

    touch "$SSH_CONFIG"
    chmod 600 "$SSH_CONFIG"

    awk -v begin="$BEGIN_MARKER" -v end="$END_MARKER" '
        $0 == begin { skip = 1; next }
        $0 == end { skip = 0; next }
        skip != 1 { print }
    ' "$SSH_CONFIG" > "$TMP_CONFIG"

    {
        printf "%s\n" "$BEGIN_MARKER"
        printf "Host %s\n" "$HOST_ALIAS"
        printf "    HostName %s\n" "$SERVER_HOST"
        printf "    User %s\n" "$SSH_USER"
        printf "    Port %s\n" "$SSH_PORT"
        printf "    IdentityFile %s\n" "$KEY_FILE"
        printf "    IdentitiesOnly yes\n"
        printf "    ServerAliveInterval 30\n"
        printf "    ServerAliveCountMax 3\n"
        printf "%s\n" "$END_MARKER"
    } >> "$TMP_CONFIG"

    mv "$TMP_CONFIG" "$SSH_CONFIG"
    chmod 600 "$SSH_CONFIG"
    printf "%b\n" "${GREEN}✓ SSH config host ready: $HOST_ALIAS${RC}"
}

detectShellRc() {
    SHELL_NAME=$(basename "${SHELL:-sh}")
    case "$SHELL_NAME" in
        zsh)
            SHELL_RC="$HOME/.zshrc"
            ;;
        bash)
            SHELL_RC="$HOME/.bashrc"
            ;;
        *)
            SHELL_RC="$HOME/.profile"
            ;;
    esac
}

writeShellAlias() {
    printf "%b" "${YELLOW}Create short command alias? [Y/n]: ${RC}"
    read -r create_alias
    case "$create_alias" in
        n|N|no|NO)
            printf "%b\n" "${CYAN}→ Short command skipped. SSH config host is: $HOST_ALIAS${RC}"
            return 0
            ;;
        *)
            ;;
    esac

    printf "%b" "${YELLOW}Short command name [${HOST_ALIAS}]: ${RC}"
    read -r SHELL_ALIAS
    SHELL_ALIAS="${SHELL_ALIAS:-$HOST_ALIAS}"

    case "$SHELL_ALIAS" in
        *[!A-Za-z0-9_-]*|"")
            printf "%b\n" "${RED}Short command can only use letters, numbers, underscore, and dash.${RC}"
            exit 1
            ;;
    esac

    detectShellRc
    BEGIN_MARKER="# BEGIN rahul ssh shell alias: $SHELL_ALIAS"
    END_MARKER="# END rahul ssh shell alias: $SHELL_ALIAS"
    TMP_RC=$(mktemp "$SSH_DIR/shellrc.XXXXXX")

    touch "$SHELL_RC"
    awk -v begin="$BEGIN_MARKER" -v end="$END_MARKER" '
        $0 == begin { skip = 1; next }
        $0 == end { skip = 0; next }
        skip != 1 { print }
    ' "$SHELL_RC" > "$TMP_RC"

    {
        printf "%s\n" "$BEGIN_MARKER"
        printf "alias %s='ssh %s'\n" "$SHELL_ALIAS" "$HOST_ALIAS"
        printf "%s\n" "$END_MARKER"
    } >> "$TMP_RC"

    mv "$TMP_RC" "$SHELL_RC"
    printf "%b\n" "${GREEN}✓ Short command added to $SHELL_RC: $SHELL_ALIAS${RC}"
    printf "%b\n" "${CYAN}→ Restart your shell or run: . $SHELL_RC${RC}"
}

testConnection() {
    printf "%b" "${YELLOW}Test SSH connection now? [y/N]: ${RC}"
    read -r test_now
    case "$test_now" in
        y|Y|yes|YES)
            if ssh -o BatchMode=yes -o ConnectTimeout=8 -o StrictHostKeyChecking=accept-new "$HOST_ALIAS" true; then
                printf "%b\n" "${GREEN}✓ SSH connection works${RC}"
            else
                printf "%b\n" "${YELLOW}Connection test failed. Check server IP, firewall port, and key.${RC}"
            fi
            ;;
        *)
            ;;
    esac
}

printSummary() {
    printf "%b\n" "${GREEN}========================================${RC}"
    printf "%b\n" "${GREEN}Client SSH Setup Complete${RC}"
    printf "%b\n" "${GREEN}========================================${RC}"
    printf "%b\n" "${CYAN}  Server      : ${SSH_USER}@${SERVER_HOST}${RC}"
    printf "%b\n" "${CYAN}  Port        : ${SSH_PORT}${RC}"
    printf "%b\n" "${CYAN}  Key         : ${KEY_FILE}${RC}"
    printf "%b\n" "${CYAN}  SSH config  : ${HOST_ALIAS}${RC}"
    if [ -n "${SHELL_ALIAS:-}" ]; then
        printf "%b\n" "${CYAN}  Command     : ${SHELL_ALIAS}${RC}"
    else
        printf "%b\n" "${CYAN}  Command     : not created${RC}"
    fi
    printf "%b\n" "${GREEN}========================================${RC}"
}

installSSHClient
promptConnectionDetails
ensurePrivateKey
writeSSHConfigAlias
writeShellAlias
testConnection
printSummary
