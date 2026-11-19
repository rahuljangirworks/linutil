#!/bin/sh -e

# Configure standard OpenSSH aliases for a home lab destination.
# Reruns update the managed aliases without replacing existing keys.

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
. "$SCRIPT_DIR/../../common-script.sh"

SSH_DIR="$HOME/.ssh"
SSH_CONFIG="$SSH_DIR/config"
DEFAULT_KEY_FILE="$SSH_DIR/id_ed25519_homelab"
LOCAL_USER=$(id -un)
LOCAL_UID=$(id -u)

fail() {
    printf '%b%s%b\n' "$RED" "$1" "$RC" >&2
    exit 1
}

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

validHost() {
    case "$1" in
        ''|-*|*[!A-Za-z0-9._:-]*) return 1 ;;
    esac
}

promptConnectionDetails() {
    printf '%s' 'Destination name (such as pve, omv, 5820 or 480): '
    IFS= read -r DESTINATION
    case "$DESTINATION" in
        ''|-*|*[!A-Za-z0-9_-]*) fail "Use letters, numbers, hyphens or underscores for the destination name." ;;
    esac
    LAN_ALIAS="$DESTINATION"
    TS_ALIAS="$DESTINATION-ts"

    printf '%s' 'Verified LAN hostname or IP: '
    IFS= read -r LAN_HOST
    validHost "$LAN_HOST" || fail "Enter a LAN hostname or an unbracketed IP address."

    printf '%s' 'Full Tailscale MagicDNS name (leave blank for LAN only): '
    IFS= read -r TS_HOST
    case "$TS_HOST" in
        '') ;;
        *[!A-Za-z0-9.-]*|-*|.*) fail "Enter the full MagicDNS name shown in Tailscale." ;;
        *.*.ts.net) ;;
        *) fail "Enter the full MagicDNS name shown in Tailscale, ending in .ts.net." ;;
    esac

    printf 'Destination login user [%s]: ' "$LOCAL_USER"
    IFS= read -r SSH_USER
    SSH_USER=${SSH_USER:-$LOCAL_USER}
    case "$SSH_USER" in
        -*|*[!A-Za-z0-9_.-]*) fail "Enter a valid destination login user." ;;
    esac

    printf '%s' 'Verified OpenSSH port for this destination: '
    IFS= read -r SSH_PORT
    case "$SSH_PORT" in
        ''|*[!0-9]*) fail "Enter the verified SSH port as a number from 1 to 65535." ;;
    esac
    [ "${#SSH_PORT}" -le 5 ] && [ "$SSH_PORT" -ge 1 ] && [ "$SSH_PORT" -le 65535 ] ||
        fail "Enter the verified SSH port as a number from 1 to 65535."
    SSH_PORT=$(awk -v port="$SSH_PORT" 'BEGIN { print port + 0 }')

    printf '%s' 'Shared verified known_hosts name or IP (leave blank to verify each path separately): '
    IFS= read -r HOST_KEY_ALIAS
    if [ -n "$HOST_KEY_ALIAS" ]; then
        validHost "$HOST_KEY_ALIAS" || fail "Enter the verified host-key name or IP."
    fi

    printf 'Local Ed25519 key path [%s]: ' "$DEFAULT_KEY_FILE"
    IFS= read -r KEY_FILE
    KEY_FILE=${KEY_FILE:-$DEFAULT_KEY_FILE}
    case "$KEY_FILE" in
        \~/*) KEY_FILE="$HOME/${KEY_FILE#??}" ;;
    esac
    case "$KEY_FILE" in
        *[!A-Za-z0-9._/-]*) fail "Enter a key path without spaces or special characters." ;;
        /*) ;;
        *) fail "Enter an absolute key path or a path starting with ~/." ;;
    esac
}

confirmConnectionPlan() {
    printf '\n%s\n' 'Planned SSH client changes:'
    printf '  Destination: %s (login user %s)\n' "$DESTINATION" "$SSH_USER"
    printf '  Local alias: %s -> %s:%s\n' "$LAN_ALIAS" "$LAN_HOST" "$SSH_PORT"
    if [ -n "$TS_HOST" ]; then
        printf '  Remote alias: %s -> %s:%s\n' "$TS_ALIAS" "$TS_HOST" "$SSH_PORT"
    fi
    if [ -n "$HOST_KEY_ALIAS" ]; then
        printf '  Shared verified host-key alias: %s\n' "$HOST_KEY_ALIAS"
    else
        printf '%s\n' '  Verify and pin host keys separately for each alias.'
    fi
    printf '  Ed25519 key: %s\n' "$KEY_FILE"
    if [ -f "$KEY_FILE" ]; then
        printf '%s\n' '  Reuse and verify the existing key; empty-passphrase keys will be rejected.'
    else
        printf '%s\n' '  Create a new passphrase-protected Ed25519 key if the path is unused.'
    fi
    printf '%s\n' '  Write or update only this destination’s managed SSH config block.'
    if ! command_exists ssh ssh-keygen; then
        printf '%s\n' '  Install the OpenSSH client first if it is missing.'
    fi
    printf '%s' 'Type APPLY to continue: '
    IFS= read -r answer || exit 0
    [ "$answer" = APPLY ] || {
        printf '%s\n' 'No changes applied.'
        exit 0
    }
}

# Fail on incomplete blocks so a rerun cannot discard unrelated configuration.
removeManagedBlock() {
    awk -v begin="$2" -v end="$3" '
        $0 == begin { if (skip || found) exit 1; found = skip = 1; next }
        $0 == end { if (!skip) exit 1; skip = 0; next }
        skip && /^# (BEGIN|END) rahul / { exit 1 }
        !skip { print }
        END { if (skip) exit 1 }
    ' "$1"
}

writeAlias() {
    printf 'Host %s\n' "$1"
    printf '    HostName %s\n' "$2"
    printf '    User %s\n' "$SSH_USER"
    printf '    Port %s\n' "$SSH_PORT"
    printf '    IdentityFile %s\n' "$KEY_FILE"
    printf '    IdentitiesOnly yes\n'
    printf '    StrictHostKeyChecking yes\n'
    printf '    ForwardAgent no\n'
    printf '    ProxyCommand none\n'
    printf '    CanonicalizeHostname no\n'
    printf '    ServerAliveInterval 30\n'
    printf '    ServerAliveCountMax 3\n'
    if [ -n "$HOST_KEY_ALIAS" ]; then
        printf '    HostKeyAlias %s\n' "$HOST_KEY_ALIAS"
    fi
}

validateAlias() {
    ssh -GT -F "$WORK_DIR/config" "$1" > "$WORK_DIR/effective" ||
        fail "OpenSSH could not parse the proposed configuration for $1."
    awk -v host="$2" -v login="$SSH_USER" -v port="$SSH_PORT" -v identity="$KEY_FILE" \
        -v key_alias="$HOST_KEY_ALIAS" '
        $1 == "hostname" && tolower($2) == tolower(host) { found_host = 1 }
        $1 == "user" && $2 == login { found_user = 1 }
        $1 == "port" && $2 == port { found_port = 1 }
        $1 == "identityfile" && $2 == identity { found_identity = 1 }
        $1 == "identitiesonly" && $2 == "yes" { only = 1 }
        $1 == "stricthostkeychecking" && ($2 == "yes" || $2 == "true") { strict = 1 }
        $1 == "forwardagent" && ($2 == "no" || $2 == "false") { forward_disabled = 1 }
        $1 == "hostkeyalias" { effective_key_alias = $2 }
        ($1 == "proxycommand" || $1 == "proxyjump") && $2 != "none" { proxy_enabled = 1 }
        END {
            exit !(found_host && found_user && found_port && found_identity && only &&
                strict && forward_disabled && !proxy_enabled && effective_key_alias == key_alias)
        }
    ' "$WORK_DIR/effective" || fail "The effective SSH settings for $1 do not match the requested settings."
}

stageSSHConfig() {
    if [ -L "$SSH_CONFIG" ] || { [ -e "$SSH_CONFIG" ] && [ ! -f "$SSH_CONFIG" ]; }; then
        fail "$SSH_CONFIG must be a regular file. Manage this config through its existing source."
    fi

    CONFIG_EXISTS=no
    if [ -f "$SSH_CONFIG" ]; then
        CONFIG_EXISTS=yes
        [ "$(stat -Lc '%u' -- "$SSH_CONFIG")" = "$LOCAL_UID" ] || fail "$SSH_CONFIG must be owned by $LOCAL_USER."
        cat -- "$SSH_CONFIG" > "$WORK_DIR/original"
    else
        : > "$WORK_DIR/original"
    fi

    BEGIN_MARKER="# BEGIN rahul home lab ssh: $DESTINATION"
    END_MARKER="# END rahul home lab ssh: $DESTINATION"
    removeManagedBlock "$WORK_DIR/original" "$BEGIN_MARKER" "$END_MARKER" > "$WORK_DIR/remainder" ||
        fail "The existing managed SSH block is incomplete or duplicated. Review $SSH_CONFIG."

    # Leave explicit Host entries outside this script's block to their owner.
    awk -v lan="$LAN_ALIAS" -v remote="${TS_HOST:+$TS_ALIAS}" '
        /^[[:space:]]*[Hh][Oo][Ss][Tt][[:space:]=]/ {
            sub(/^[[:space:]]*[Hh][Oo][Ss][Tt][[:space:]=]+/, "")
            count = split($0, names, /[[:space:]]+/)
            for (i = 1; i <= count; i++) {
                if (names[i] ~ /^#/) break
                gsub(/"/, "", names[i])
                if (tolower(names[i]) == tolower(lan) ||
                    (remote != "" && tolower(names[i]) == tolower(remote))) exit 1
            }
        }
    ' "$WORK_DIR/remainder" ||
        fail "An SSH alias with this name already exists. Choose another destination name or review the existing Host entry."

    {
        printf '%s\n' "$BEGIN_MARKER"
        writeAlias "$LAN_ALIAS" "$LAN_HOST"
        if [ -n "$TS_HOST" ]; then
            writeAlias "$TS_ALIAS" "$TS_HOST"
        fi
        # Global directives in the original config must still apply to all hosts.
        printf '%s\n' 'Host *' "$END_MARKER"
        cat -- "$WORK_DIR/remainder"
    } > "$WORK_DIR/config"

    validateAlias "$LAN_ALIAS" "$LAN_HOST"
    if [ -n "$TS_HOST" ]; then
        validateAlias "$TS_ALIAS" "$TS_HOST"
    fi
}

requirePassphrase() {
    if ssh-keygen -y -P '' -f "$1" >/dev/null 2>&1; then
        fail "This key has an empty passphrase. Use a passphrase-protected key generated on this client."
    fi
}

readEd25519PublicKey() {
    PUBLIC_KEY=$(awk 'NR == 1 && $1 == "ssh-ed25519" && NF >= 2 { print $1, $2 }' "$WORK_DIR/public-key")
    [ -n "$PUBLIC_KEY" ] || fail "Select an Ed25519 key generated on this client."
}

verifyLocalKey() {
    [ "$(stat -Lc '%u' -- "$1")" = "$LOCAL_UID" ] ||
        fail "The selected key must be owned by $LOCAL_USER."
    case "$(stat -Lc '%a' -- "$1")" in
        400|600) ;;
        *) fail "The private key must have mode 600 or 400." ;;
    esac
    requirePassphrase "$1"
    ssh-keygen -y -f "$1" > "$WORK_DIR/public-key" ||
        fail "OpenSSH could not read the private key."
    readEd25519PublicKey
}

ensureLocalKey() {
    if [ -f "$KEY_FILE" ]; then
        printf '%s\n' 'Use an existing key generated on this client. Unlock it to verify the key.'
        verifyLocalKey "$KEY_FILE"
        if [ -e "$KEY_FILE.pub" ] || [ -L "$KEY_FILE.pub" ]; then
            [ -f "$KEY_FILE.pub" ] &&
                [ "$(awk 'NR == 1 { print $1, $2 }' "$KEY_FILE.pub")" = "$PUBLIC_KEY" ] ||
                fail "The existing .pub file does not match the selected key. Review the pair before proceeding."
        fi
        return
    fi

    [ ! -e "$KEY_FILE" ] && [ ! -L "$KEY_FILE" ] && [ ! -e "$KEY_FILE.pub" ] && [ ! -L "$KEY_FILE.pub" ] ||
        fail "The requested key path is already in use."
    [ "$(dirname -- "$KEY_FILE")" = "$SSH_DIR" ] ||
        fail "Choose a path directly under $SSH_DIR to generate a new key."

    printf 'Generate a new passphrase-protected Ed25519 key at %s? [y/N] ' "$KEY_FILE"
    IFS= read -r CREATE_KEY
    case "$CREATE_KEY" in
        y|Y|yes|YES) ;;
        *) fail "Key creation cancelled." ;;
    esac

    ssh-keygen -q -t ed25519 -f "$WORK_DIR/key" -C "$LOCAL_USER@$(hostname)"
    requirePassphrase "$WORK_DIR/key"
    cp -- "$WORK_DIR/key.pub" "$WORK_DIR/public-key"
    readEd25519PublicKey

    # Link without replacing an existing key or public key, even if one appears during the prompt.
    ln -T -- "$WORK_DIR/key.pub" "$KEY_FILE.pub" || fail "Could not create the public key at $KEY_FILE.pub."
    ln -T -- "$WORK_DIR/key" "$KEY_FILE" || fail "Could not create the private key at $KEY_FILE."
}

cleanup() {
    # Remove a public key only when this run published it without its private key.
    if [ "$WORK_DIR/key.pub" -ef "$KEY_FILE.pub" ] && ! [ "$WORK_DIR/key" -ef "$KEY_FILE" ]; then
        rm -f -- "$KEY_FILE.pub"
    fi
    rm -rf -- "$WORK_DIR"
}

installSSHConfig() {
    if [ -L "$SSH_CONFIG" ]; then
        fail "$SSH_CONFIG changed during setup. Run the setup again."
    fi
    if [ "$CONFIG_EXISTS" = yes ]; then
        if [ ! -f "$SSH_CONFIG" ] || ! cmp -s "$WORK_DIR/original" "$SSH_CONFIG"; then
            fail "$SSH_CONFIG changed during setup. Run the setup again."
        fi
    elif [ -e "$SSH_CONFIG" ]; then
        fail "$SSH_CONFIG appeared during setup. Run the setup again."
    fi
    mv -fT -- "$WORK_DIR/config" "$SSH_CONFIG"
}

writeShellAlias() (
    printf 'Create an optional shell shortcut for %s? [y/N] ' "$LAN_ALIAS"
    IFS= read -r CREATE_ALIAS || return 0
    case "$CREATE_ALIAS" in
        y|Y|yes|YES) ;;
        *) return 0 ;;
    esac
    printf 'Shortcut name [%s]: ' "$LAN_ALIAS"
    IFS= read -r SHELL_ALIAS
    SHELL_ALIAS=${SHELL_ALIAS:-$LAN_ALIAS}
    case "$SHELL_ALIAS" in
        -*|*[!A-Za-z0-9_-]*) fail "Use letters, numbers, hyphens or underscores for the shortcut." ;;
    esac

    case "${SHELL##*/}" in
        zsh) SHELL_RC="$HOME/.zshrc" ;;
        bash) SHELL_RC="$HOME/.bashrc" ;;
        *) SHELL_RC="$HOME/.profile" ;;
    esac
    if [ -L "$SHELL_RC" ] || { [ -e "$SHELL_RC" ] && [ ! -f "$SHELL_RC" ]; }; then
        fail "Manage the shell shortcut through the existing source of $SHELL_RC."
    fi

    RC_TMP=$(mktemp "${SHELL_RC}.rahul-ssh.XXXXXX")
    trap 'rm -f -- "$RC_TMP"' 0
    trap 'exit 1' HUP INT TERM
    BEGIN_MARKER="# BEGIN rahul ssh shell alias: $SHELL_ALIAS"
    END_MARKER="# END rahul ssh shell alias: $SHELL_ALIAS"
    if [ -f "$SHELL_RC" ]; then
        [ "$(stat -Lc '%u' -- "$SHELL_RC")" = "$LOCAL_UID" ] || fail "$SHELL_RC must be owned by $LOCAL_USER."
        removeManagedBlock "$SHELL_RC" "$BEGIN_MARKER" "$END_MARKER" > "$RC_TMP" ||
            fail "The existing shortcut block is incomplete or duplicated in $SHELL_RC."
        chmod "$(stat -c '%a' -- "$SHELL_RC")" "$RC_TMP"
    fi
    {
        printf '%s\n' "$BEGIN_MARKER"
        printf "alias %s='ssh %s'\n" "$SHELL_ALIAS" "$LAN_ALIAS"
        printf '%s\n' "$END_MARKER"
    } >> "$RC_TMP"
    mv -fT -- "$RC_TMP" "$SHELL_RC"
    printf 'Shortcut added to %s. Open a new shell to use %s.\n' "$SHELL_RC" "$SHELL_ALIAS"
)

testConnection() {
    printf 'Test a fresh public-key login on %s now? [y/N] ' "$1"
    IFS= read -r TEST_NOW || return 0
    case "$TEST_NOW" in
        y|Y|yes|YES)
            if ! ssh -n -S none -o PreferredAuthentications=publickey -o ConnectTimeout=8 "$1" hostname; then
                printf 'Login to %s failed. Verify the stored host key, route, port, and authorized public key.\n' "$1" >&2
                return 1
            fi
            ;;
    esac
}

[ "$LOCAL_UID" -ne 0 ] || fail "Run Client SSH as the local account that will use the key."
[ -t 0 ] || fail "Run Client SSH in a terminal so you can enter the destination, port, and key choices."
promptConnectionDetails
confirmConnectionPlan
installSSHClient
umask 077
mkdir -p -- "$SSH_DIR"
[ "$(stat -Lc '%u' -- "$SSH_DIR")" = "$LOCAL_UID" ] || fail "$SSH_DIR must be owned by $LOCAL_USER."
chmod 700 -- "$SSH_DIR"

WORK_DIR="$SSH_DIR/.rahul-ssh-setup.lock"
mkdir -- "$WORK_DIR" || fail "Another Client SSH setup may be active. Review $WORK_DIR before retrying."
trap cleanup 0
trap 'exit 1' HUP INT TERM
stageSSHConfig
ensureLocalKey
installSSHConfig

printf 'SSH alias ready: %s\n' "$LAN_ALIAS"
if [ -n "$TS_HOST" ]; then
    printf 'SSH alias ready: %s\n' "$TS_ALIAS"
fi
printf '%s\n' 'Authorize this public key on the selected destination only:'
printf '%s\n' "$PUBLIC_KEY"
ssh-keygen -lf "$WORK_DIR/public-key"
printf '%s\n' 'Verify the server host key through its console or an already-trusted path before adding it to known_hosts.'

writeShellAlias
cleanup
trap - 0 HUP INT TERM
TEST_FAILED=0
testConnection "$LAN_ALIAS" || TEST_FAILED=1
if [ -n "$TS_HOST" ]; then
    testConnection "$TS_ALIAS" || TEST_FAILED=1
fi
exit "$TEST_FAILED"
