#!/bin/sh -e

# Audit this Linux machine, then run the existing interactive OpenSSH client
# and/or server setup. The server and firewall controls remain separately gated.

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
CLIENT_SETUP="$SCRIPT_DIR/ssh-client-alias-setup.sh"
SERVER_SETUP="$SCRIPT_DIR/secure-ssh.sh"
FIREWALL_AUDIT="$SCRIPT_DIR/../security/rahul-firewall-baseline.sh"

fail() {
    printf '%s\n' "$*" >&2
    exit 1
}

requireTerminal() {
    [ -t 0 ] || fail 'Run Home Lab SSH Setup in a terminal so you can answer the setup questions.'
}

auditClient() {
    printf '\n%s\n' 'OpenSSH client and key inventory'
    printf 'Local user: %s\n' "$(id -un)"
    if command -v ssh >/dev/null 2>&1; then
        ssh -V 2>&1 || :
    else
        printf '%s\n' 'OpenSSH client: not installed'
    fi
    if command -v ssh-keygen >/dev/null 2>&1; then
        printf '%s\n' 'Existing public-key fingerprints:'
        found_key=no
        for key in "$HOME"/.ssh/*.pub; do
            [ -f "$key" ] || continue
            found_key=yes
            printf '%s: ' "${key##*/}"
            ssh-keygen -lf "$key" || :
        done
        [ "$found_key" = yes ] || printf '%s\n' '  No public key files found.'
    else
        printf '%s\n' 'ssh-keygen: not installed'
    fi
    if [ -e "$HOME/.ssh/config" ]; then
        ls -ld "$HOME/.ssh" "$HOME/.ssh/config" 2>/dev/null || :
    else
        printf '%s\n' 'SSH client config: not present'
    fi

    printf '\n%s\n' 'Tailscale status'
    if command -v tailscale >/dev/null 2>&1; then
        tailscale version 2>/dev/null | head -n 1 || :
        tailscale status 2>&1 || :
        tailscale ip 2>&1 || printf '%s\n' 'Tailscale is installed but not connected.'
    else
        printf '%s\n' 'Tailscale: not installed'
    fi
}

auditUsers() {
    printf '\n%s\n' 'Current sessions and interactive local accounts'
    if command -v who >/dev/null 2>&1; then
        who || :
    fi
    uid_min=$(awk '$1 == "UID_MIN" {print $2; exit}' /etc/login.defs 2>/dev/null)
    uid_min=${uid_min:-1000}
    if command -v getent >/dev/null 2>&1; then
        account_source=$(getent passwd 2>/dev/null || cat /etc/passwd)
    else
        account_source=$(cat /etc/passwd)
    fi
    interactive_accounts=$(printf '%s\n' "$account_source" |
        awk -F: -v uid_min="$uid_min" \
            '$3 >= uid_min && $7 !~ /(nologin|false)$/ {printf "  %s (UID %s, home %s)\n", $1, $3, $6}')
    if [ -n "$interactive_accounts" ]; then
        printf '%s\n' "$interactive_accounts"
    else
        printf '%s\n' '  No interactive non-system accounts found.'
    fi
}

auditMachine() {
    printf '%s\n' 'Step 1: Read-only audit of this machine'
    printf '%s\n' 'This audit does not change settings. It may request sudo to inspect the SSH server and firewall.'
    printf '\n%s\n' 'OpenSSH server audit'
    if ! (cd "$SCRIPT_DIR" && sh "$SERVER_SETUP" --audit); then
        printf '%s\n' 'OpenSSH server audit had an error; review the output before choosing server setup.'
    fi
    auditClient
    auditUsers
    printf '\n%s\n' 'Host firewall audit'
    if ! (cd "$SCRIPT_DIR" && sh "$FIREWALL_AUDIT" --audit); then
        printf '%s\n' 'Firewall audit had an error; review firewall status manually before permitting SSH.'
    fi
}

askMode() {
    printf '\n%s\n' 'Step 2: Choose what this machine should do'
    printf '%s\n' '  [c] Configure this machine as an SSH client'
    printf '%s\n' '  [s] Harden this machine as an SSH server'
    printf '%s\n' '  [b] Configure client and server (default)'
    printf '%s\n' '  [a] Finish after the audit'
    printf '%s' 'Choice [b]: '
    IFS= read -r MODE || exit 0
    MODE=${MODE:-b}
    case "$MODE" in
        c|C) MODE=client ;;
        s|S) MODE=server ;;
        b|B) MODE=both ;;
        a|A) MODE=audit ;;
        *) fail 'Choose c, s, b or a.' ;;
    esac
}

runClientSetup() {
    while :; do
        printf '\n%s\n' 'Client SSH setup'
        printf '%s\n' 'The LAN alias uses the short destination name; the optional Tailscale alias adds -ts. The workflow asks for the destination, verified port, host-key identity, and local key, then requires APPLY.'
        if ! (cd "$SCRIPT_DIR" && sh "$CLIENT_SETUP"); then
            printf '%s\n' 'Client SSH setup did not complete. Review the error above.' >&2
            return 1
        fi
        printf '\n%s\n' 'The client workflow never copies a private key to the server. Authorize its displayed public key on the chosen destination through a trusted path.'
        printf '%s' 'Configure another SSH destination from this client? [y/N]: '
        IFS= read -r AGAIN || return 0
        case "$AGAIN" in
            y|Y|yes|YES) ;;
            *) return 0 ;;
        esac
    done
}

runServerSetup() {
    printf '\n%s\n' 'Server SSH setup'
    printf '%s\n' 'This hardens only the machine running this wizard. It preserves the current effective SSH port and requires a verified fresh key login, account, sudo access, and typed APPLY.'
    printf '%s\n' 'For safe hardening, run the server step from a verified OpenSSH session after the client public key is authorized. Keep a recovery console available.'
    printf '%s\n' 'The server step does not change firewall rules, Tailscale settings, RustDesk, or router port forwarding.'
    if [ -z "${SSH_CONNECTION:-}" ]; then
        printf '%s\n' 'This terminal has no SSH_CONNECTION value. If you are at the local console, finish client setup now and rerun the server step from a fresh, verified SSH session.'
        printf '%s' 'Continue to the server prompts anyway, so you can enter details from a separate verified session? [y/N]: '
        IFS= read -r CONTINUE_SERVER || return 0
        case "$CONTINUE_SERVER" in
            y|Y|yes|YES) ;;
            *)
                printf '%s\n' 'Server step skipped. No server changes were applied.'
                return 0
                ;;
        esac
    fi
    (cd "$SCRIPT_DIR" && sh "$SERVER_SETUP" --configure)
}

requireTerminal
cd "$SCRIPT_DIR"
printf '%s\n' 'Home Lab SSH Setup'
printf '%s\n' 'This wizard audits and configures only the machine where you run it. Run it on each home-lab device you want to set up.'
auditMachine
askMode

case "$MODE" in
    audit)
        printf '\n%s\n' 'Audit complete. No setup was applied.'
        ;;
    client)
        runClientSetup
        ;;
    server)
        runServerSetup
        ;;
    both)
        runClientSetup
        runServerSetup
        ;;
esac
