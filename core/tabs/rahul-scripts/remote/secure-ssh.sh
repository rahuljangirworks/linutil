#!/bin/sh -e

# Audit OpenSSH, with optional authentication hardening for ordinary Linux hosts.

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
. "$SCRIPT_DIR/../../common-script.sh"

SSHD_CONFIG=/etc/ssh/sshd_config
DROP_IN_DIR=/etc/ssh/sshd_config.d
HARDENING_CONFIG="$DROP_IN_DIR/00-linutil-homelab.conf"
LEGACY_CONFIG="$DROP_IN_DIR/00-hardening.conf"
MANAGED_HEADER='# Managed by Linutil home lab SSH'
BASELINE='PubkeyAuthentication yes
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin no
MaxAuthTries 3
LoginGraceTime 30
X11Forwarding no
AllowAgentForwarding no'

fail() {
    printf '%s\n' "$*" >&2
    exit 1
}

findDaemon() {
    if [ -x /usr/sbin/sshd ]; then
        printf '%s\n' /usr/sbin/sshd
    else
        command -v sshd
    fi
}

runAsAdmin() {
    "$ESCALATION_TOOL" "$@"
}

effectiveConfig() {
    runAsAdmin "$SSHD" -T -f "$SSHD_CONFIG" "$@"
}

printAudit() {
    printf 'Host: %s\n' "$(hostname)"
    if [ -r /etc/os-release ]; then
        awk -F= '$1 == "PRETTY_NAME" {print "OS: " $2}' /etc/os-release
    fi
    if command -v ip >/dev/null 2>&1; then
        ip -br address || :
    fi
    if command -v ss >/dev/null 2>&1; then
        printf '\nActive TCP listeners:\n'
        ss -lnt || :
    fi
    if command -v tailscale >/dev/null 2>&1; then
        printf '\nTailscale addresses:\n'
        tailscale ip || :
    fi
    if [ -n "$SSHD" ]; then
        "$SSHD" -V 2>&1 || :
    fi
    if command -v ssh-keygen >/dev/null 2>&1; then
        printf '\nHost public-key fingerprints:\n'
        for key in /etc/ssh/ssh_host_*.pub; do
            [ -f "$key" ] || continue
            ssh-keygen -lf "$key" || :
        done
    fi
}

printLoginInstructions() {
    cat <<'INSTRUCTIONS'

Verify the host-key fingerprint through the console or a known trusted path.
On the admin client, use a passphrase-protected Ed25519 key. Install only the
client's public key on the named server account. Use the account's effective
AuthorizedKeysFile location and ownership. For ~/.ssh/authorized_keys use
mode 0700 for ~/.ssh and 0600 for authorized_keys.

From each approved LAN or Tailscale path, use a fresh SSH session with
ssh -S none -o PreferredAuthentications=publickey <your-alias>
and verify the account and required sudo access. Keep your existing session
and recovery console open.
INSTRUCTIONS
}

readSessionContext() {
    printf 'Paste SSH_CONNECTION from the verified %s session: ' "$1" >&2
    IFS=' ' read -r client_addr client_port server_addr server_port extra || return 1
    case "$client_addr" in ''|*[!0-9a-fA-F:.]*) return 1 ;; esac
    case "$server_addr" in ''|*[!0-9a-fA-F:.]*) return 1 ;; esac
    for port in "$client_port" "$server_port"; do
        case "$port" in ''|*[!0-9]*) return 1 ;; esac
        [ "$port" -gt 0 ] && [ "$port" -le 65535 ] || return 1
    done
    [ -z "$extra" ] || return 1
    printf 'user=%s,host=%s,addr=%s,laddr=%s,lport=%s\n' \
        "$ADMIN_USER" "$client_addr" "$client_addr" "$server_addr" "$server_port"
}

confirmSessionPort() {
    path_name=$1
    session_context=$2
    session_port=$(printf '%s\n' "$session_context" |
        sed -n 's/.*lport=\([0-9][0-9]*\).*/\1/p')
    [ -n "$session_port" ] || fail "Could not read the verified $path_name SSH port."

    session_config=$(effectiveConfig -C "$session_context") ||
        fail "Could not read effective OpenSSH settings for the verified $path_name session."
    current_ports=$(printf '%s\n' "$session_config" |
        awk '$1 == "port" {print $2}' | sort -nu | tr '\n' ' ')
    case " $current_ports " in
        *" $session_port "*) ;;
        *) fail "The verified $path_name port $session_port is not an effective OpenSSH listener. Review socket activation or port forwarding manually." ;;
    esac

    printf 'Verified %s SSH session uses TCP port %s. Current effective listener ports are %s.\n' \
        "$path_name" "$session_port" "$current_ports"
    printf 'Enter %s to confirm this port while hardening authentication: ' "$session_port"
    IFS=' ' read -r confirmed_port || exit 0
    [ "$confirmed_port" = "$session_port" ] || {
        printf 'No changes applied. Connect through the port you want to use, then rerun the audit.\n'
        exit 0
    }
}

verifyEffective() {
    required=$(printf '%s\n' "$BASELINE" | tr '[:upper:]' '[:lower:]')
    while IFS= read -r setting; do
        if ! printf '%s\n' "$2" | grep -Fxq -- "$setting"; then
            printf 'Required setting is ineffective (%s): %s\n' "$3" "$setting" >&2
            return 1
        fi
    done <<EOF
$required
EOF

    # All other settings, including listeners and host keys, must stay effective.
    baseline_pattern='^(pubkeyauthentication|passwordauthentication|kbdinteractiveauthentication|permitrootlogin|maxauthtries|logingracetime|x11forwarding|allowagentforwarding) '
    old_settings=$(printf '%s\n' "$1" | sed -E "/$baseline_pattern/d")
    new_settings=$(printf '%s\n' "$2" | sed -E "/$baseline_pattern/d")
    if [ "$old_settings" != "$new_settings" ]; then
        printf 'The proposed configuration changes unrelated settings (%s).\n' "$3" >&2
        return 1
    fi
}

verifyRootPolicy() {
    root_config=$(effectiveConfig -C "user=root,${1#*,}") ||
        fail "Cannot validate the root policy for the $2 path."
    printf '%s\n' "$root_config" | grep -Fxq 'permitrootlogin no' ||
        fail "An SSH Match rule still permits root login on the $2 path."
}

selectReloadService() {
    command -v systemctl >/dev/null 2>&1 ||
        fail 'Automatic apply requires an active, reloadable systemd OpenSSH service.'
    SERVICE=
    for unit in ssh.service sshd.service; do
        if systemctl is-active --quiet "$unit"; then
            service_id=$(systemctl show --property=Id --value "$unit")
            [ -n "$service_id" ] || fail "Cannot identify the active service for $unit."
            [ -z "$SERVICE" ] || [ "$SERVICE" = "$service_id" ] ||
                fail 'Multiple OpenSSH services are active. Use the host-specific procedure.'
            SERVICE=$service_id
        fi
    done
    [ -n "$SERVICE" ] && [ "$(systemctl show --property=CanReload --value "$SERVICE")" = yes ] ||
        fail 'No active, reloadable OpenSSH service was found. Review the service or socket manually.'
    exec_start=$(systemctl show --property=ExecStart --value "$SERVICE")
    if printf '%s\n' "$exec_start" | grep -Eq '[[:space:]]-[fo46p]'; then
        fail 'The SSH service has command-line overrides. Validate the running configuration manually.'
    fi
}

priorDropInIntact() {
    runAsAdmin test ! -L "$HARDENING_CONFIG" || return 1
    if [ "$HAD_CONFIG" = yes ]; then
        runAsAdmin cmp -s -- "$HARDENING_CONFIG" "$BACKUP_DIR/previous.conf"
    else
        runAsAdmin test ! -e "$HARDENING_CONFIG"
    fi
}

restoreConfig() {
    if runAsAdmin test -L "$HARDENING_CONFIG" ||
        ! runAsAdmin cmp -s -- "$HARDENING_CONFIG" "$BACKUP_DIR/proposed.conf"; then
        if [ "$RELOAD_ATTEMPTED" = no ] && priorDropInIntact; then
            return 0
        fi
        printf 'The active drop-in changed during rollout. Recovery files: %s\n' "$BACKUP_DIR" >&2
        return 1
    fi
    if [ "$HAD_CONFIG" = yes ]; then
        runAsAdmin cp -a -- "$BACKUP_DIR/previous.conf" "$LOCK_DIR/restore" &&
            runAsAdmin mv -fT -- "$LOCK_DIR/restore" "$HARDENING_CONFIG" || return 1
    else
        runAsAdmin rm -- "$HARDENING_CONFIG" || return 1
    fi
    if [ "$RELOAD_ATTEMPTED" = yes ]; then
        runAsAdmin "$SSHD" -t -f "$SSHD_CONFIG" &&
            runAsAdmin systemctl reload "$SERVICE" || return 1
    fi
    printf 'Restored the prior OpenSSH configuration.\n' >&2
}

finishApply() {
    result=$1
    trap - 0 HUP INT TERM
    if [ "$INSTALLED" = yes ] && ! restoreConfig; then
        printf 'Automatic recovery did not complete. Use your console and backup at %s.\n' "$BACKUP_DIR" >&2
        result=1
    fi
    runAsAdmin rm -f -- "$LOCK_DIR/candidate" "$LOCK_DIR/restore" || result=1
    runAsAdmin rmdir -- "$LOCK_DIR" || result=1
    exit "$result"
}

applyBaseline() {
    [ -d "$DROP_IN_DIR" ] || fail 'No OpenSSH drop-in directory. Review Include configuration manually.'
    selectReloadService

    LOCK_DIR="$DROP_IN_DIR/.linutil-homelab.lock"
    runAsAdmin mkdir -m 0700 -- "$LOCK_DIR" ||
        fail "Cannot acquire $LOCK_DIR. Check for another rollout before proceeding."
    INSTALLED=no
    RELOAD_ATTEMPTED=no
    trap 'finishApply "$?"' 0
    trap 'exit 1' HUP INT TERM

    if runAsAdmin test -L "$LEGACY_CONFIG" || runAsAdmin test -e "$LEGACY_CONFIG"; then
        fail "Legacy or custom configuration found at $LEGACY_CONFIG. Review its listeners, host keys, and overrides before migrating it manually."
    fi

    # shellcheck disable=SC2016 # awk uses its own field variables.
    if ! runAsAdmin awk 'tolower($1) == "match" {exit}
        tolower($1) == "include" {
            for (i = 2; i <= NF && $i !~ /^#/; i++)
                if ($i == "/etc/ssh/sshd_config.d/*.conf" || $i == "sshd_config.d/*.conf")
                    found = 1
        }
        END {exit !found}' "$SSHD_CONFIG"; then
        fail 'The main sshd_config needs a global Include for the drop-in directory.'
    fi

    HAD_CONFIG=no
    if runAsAdmin test -L "$HARDENING_CONFIG"; then
        fail "Resolve the symlink at $HARDENING_CONFIG manually."
    fi
    if runAsAdmin test -e "$HARDENING_CONFIG"; then
        if ! runAsAdmin test -f "$HARDENING_CONFIG" ||
            ! runAsAdmin grep -Fxq -- "$MANAGED_HEADER" "$HARDENING_CONFIG"; then
            fail "An unmanaged configuration already exists at $HARDENING_CONFIG."
        fi
        HAD_CONFIG=yes
    fi

    before_global=$(effectiveConfig) || fail 'Cannot validate the existing global SSH configuration.'
    before_lan=$(effectiveConfig -C "$LAN_CONTEXT") || fail 'Cannot validate the existing LAN session context.'
    if [ -n "$TAILNET_CONTEXT" ]; then
        before_tailnet=$(effectiveConfig -C "$TAILNET_CONTEXT") || fail 'Cannot validate the existing Tailscale session context.'
    fi
    if printf '%s\n' "$before_global" | grep -Fxq 'usedns yes'; then
        fail 'UseDNS is active. Validate hostname-dependent rules manually before applying changes.'
    fi

    BACKUP_DIR=$(runAsAdmin mktemp -d "$DROP_IN_DIR/.linutil-homelab-backup.XXXXXXXX")
    if [ "$HAD_CONFIG" = yes ]; then
        runAsAdmin cp -a -- "$HARDENING_CONFIG" "$BACKUP_DIR/previous.conf"
    fi
    printf '%s\n%s\n' "$MANAGED_HEADER" "$BASELINE" |
        runAsAdmin tee "$BACKUP_DIR/proposed.conf" >/dev/null
    runAsAdmin install -m 0644 -- "$BACKUP_DIR/proposed.conf" "$LOCK_DIR/candidate"

    priorDropInIntact || fail 'The target drop-in changed during rollout.'
    # Set the rollback flag before the atomic move so interrupts are covered.
    INSTALLED=yes
    if ! runAsAdmin mv -fT -- "$LOCK_DIR/candidate" "$HARDENING_CONFIG"; then
        INSTALLED=no
        fail 'Could not install the proposed OpenSSH drop-in.'
    fi

    runAsAdmin "$SSHD" -t -f "$SSHD_CONFIG" || fail 'The proposed configuration failed syntax validation.'
    after_global=$(effectiveConfig) || fail 'Cannot read the proposed global configuration.'
    verifyEffective "$before_global" "$after_global" global ||
        fail 'Global configuration validation failed.'
    after_lan=$(effectiveConfig -C "$LAN_CONTEXT") || fail 'Cannot read the proposed LAN configuration.'
    verifyEffective "$before_lan" "$after_lan" LAN ||
        fail 'LAN configuration validation failed.'
    verifyRootPolicy "$LAN_CONTEXT" LAN
    if [ -n "$TAILNET_CONTEXT" ]; then
        after_tailnet=$(effectiveConfig -C "$TAILNET_CONTEXT") ||
            fail 'Cannot read the proposed Tailscale configuration.'
        verifyEffective "$before_tailnet" "$after_tailnet" Tailscale ||
            fail 'Tailscale configuration validation failed.'
        verifyRootPolicy "$TAILNET_CONTEXT" Tailscale
    fi

    runAsAdmin cmp -s -- "$HARDENING_CONFIG" "$BACKUP_DIR/proposed.conf" ||
        fail 'The OpenSSH drop-in changed before service reload.'
    RELOAD_ATTEMPTED=yes
    if ! runAsAdmin systemctl reload "$SERVICE" || ! systemctl is-active --quiet "$SERVICE"; then
        fail "Reload failed for $SERVICE."
    fi
    INSTALLED=no

    printf '\nOpenSSH authentication policy applied to %s.\n' "$SERVICE"
    printf 'Retest fresh SSH login and required sudo over each approved path before closing the recovery console.\n'
    if [ "$HAD_CONFIG" = yes ]; then
        printf 'Recovery copy: %s/previous.conf\n' "$BACKUP_DIR"
        printf 'Restore it to %s if needed, then run sshd -t and reload %s.\n' "$HARDENING_CONFIG" "$SERVICE"
    else
        printf 'To roll back this first installation, remove %s, run sshd -t and reload %s.\n' "$HARDENING_CONFIG" "$SERVICE"
    fi
}

MODE=full
case "$#:$1" in
    0:) MODE=full ;;
    1:--audit) MODE=audit ;;
    1:--configure) MODE=configure ;;
    *) fail 'Usage: secure-ssh.sh [--audit|--configure]' ;;
esac

SSHD=$(findDaemon) || SSHD=
if [ "$MODE" != configure ]; then
    printAudit
fi
if [ -n "$SSHD" ] && { [ "$(id -u)" -eq 0 ] || command -v sudo >/dev/null 2>&1 || command -v doas >/dev/null 2>&1; }; then
    checkEscalationTool
    if audit_config=$(effectiveConfig); then
        if [ "$MODE" != configure ]; then
            printf '\nEffective OpenSSH settings:\n'
            printf '%s\n' "$audit_config" |
                awk '$1 ~ /^(port|addressfamily|listenaddress|permitrootlogin|passwordauthentication|kbdinteractiveauthentication|pubkeyauthentication|authorizedkeysfile|maxauthtries|logingracetime|x11forwarding|allowagentforwarding)$/'
        fi
    else
        [ "$MODE" = configure ] && fail 'Could not read the effective OpenSSH server configuration.'
        printf '\nEffective OpenSSH settings were unavailable.\n'
    fi
else
    [ "$MODE" = configure ] && fail 'OpenSSH server or privilege escalation is unavailable. Install the server and rerun the audit first.'
    printf '\nOpenSSH server or privilege escalation was unavailable.\n'
fi
if [ "$MODE" != configure ]; then
    printLoginInstructions
fi

if command -v omv-salt >/dev/null 2>&1 || [ -f /etc/openmediavault/config.xml ]; then
    printf '\nUse the OpenMediaVault web UI for SSH. Verify the named user, _ssh and sudo groups, and registered public key there.\n'
    exit 0
fi
if command -v pveversion >/dev/null 2>&1 || [ -d /etc/pve ]; then
    printf '\nUse the Proxmox-specific procedure. Check cluster status and preserve the root key access needed by cluster peers.\n'
    exit 0
fi
if [ -e "$LEGACY_CONFIG" ] || [ -L "$LEGACY_CONFIG" ]; then
    printf '\nReview %s before applying the new baseline.\n' "$LEGACY_CONFIG"
    printf 'Back it up and plan the migration from console access. Preserve verified listeners, host keys, and account access while reviewing old crypto and authentication overrides.\n'
    printf 'Verify the replacement client keys over every approved path before revoking any old shared login key.\n'
    exit 0
fi
if [ "$MODE" = audit ] || [ -z "$SSHD" ] || [ -z "$ESCALATION_TOOL" ]; then
    exit 0
fi

[ -t 0 ] || fail "Run SSH hardening in a terminal so you can confirm the login account, verified port, access paths, and apply decision."

printf '\nNamed admin account to verify (Enter to finish audit): '
IFS= read -r ADMIN_USER || exit 0
[ -n "$ADMIN_USER" ] || exit 0
case "$ADMIN_USER" in
    -*|*[!A-Za-z0-9_.-]*) fail 'Enter an existing, named administrator account.' ;;
esac
admin_uid=$(id -u "$ADMIN_USER" 2>/dev/null) ||
    fail 'The named administrator account could not be found.'
[ "$admin_uid" -gt 0 ] || fail 'Enter a non-root administrator account.'

printf '%s\n' "In the fresh login, run: printf '%s\\n' \"\$SSH_CONNECTION\""
LAN_CONTEXT=$(readSessionContext LAN) || fail 'A valid, verified LAN session is required.'
confirmSessionPort LAN "$LAN_CONTEXT"
printf 'Is a verified standard OpenSSH connection over the Tailscale interface in use? [y/N]: '
IFS= read -r has_tailnet || exit 0
TAILNET_CONTEXT=
case "$has_tailnet" in
    y|Y|yes|YES)
        TAILNET_CONTEXT=$(readSessionContext Tailscale) || fail 'A valid, verified Tailscale session is required.'
        confirmSessionPort Tailscale "$TAILNET_CONTEXT"
        ;;
    ''|n|N|no|NO) ;;
    *) fail 'Answer yes or no to confirm the required login paths.' ;;
esac

printf '\nType APPLY after verifying fresh key logins and required sudo, with a recovery console open: '
IFS= read -r confirmed || exit 0
[ "$confirmed" = APPLY ] || exit 0
applyBaseline
