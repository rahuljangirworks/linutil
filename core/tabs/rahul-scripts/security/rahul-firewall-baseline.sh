#!/bin/sh -e

# Audit the current firewall and optionally allow one verified SSH port from a trusted source.

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
. "$SCRIPT_DIR/../../common-script.sh"

export LC_ALL=C

fail() {
    printf '%s\n' "$*" >&2
    exit 1
}

detectBackends() {
    FIREWALLD_ACTIVE=no
    UFW_ACTIVE=no
    UFW_STATUS=""

    if command_exists firewall-cmd && firewall-cmd --state >/dev/null 2>&1; then
        FIREWALLD_ACTIVE=yes
    fi
    if command_exists ufw; then
        UFW_STATUS=$("$ESCALATION_TOOL" ufw status verbose) || fail "Could not read UFW status."
        if printf '%s\n' "$UFW_STATUS" | grep -qx 'Status: active'; then
            UFW_ACTIVE=yes
        fi
    fi
}

auditFirewall() {
    printf '%s\n' 'Listening TCP ports and local interfaces'
    if command_exists ss; then
        "$ESCALATION_TOOL" ss -ltnp
    fi
    if command_exists ip; then
        ip -br address
    fi

    if [ "$FIREWALLD_ACTIVE" = yes ]; then
        printf '\n%s\n' 'Active firewalld zone bindings and rules'
        "$ESCALATION_TOOL" firewall-cmd --get-active-zones
        "$ESCALATION_TOOL" firewall-cmd --list-all-zones
        printf '\n%s\n' 'Permanent firewalld rules'
        "$ESCALATION_TOOL" firewall-cmd --permanent --list-all-zones
    fi
    if [ -n "$UFW_STATUS" ]; then
        printf '\n%s\n' 'UFW status and rules' "$UFW_STATUS"
    fi

    printf '\n%s\n' \
        'Review any SSH service, port, port range, or allow policy that admits unapproved IPv4 or IPv6 sources.' \
        'Verify SSH is private at the router and on the host. Traffic on the same LAN may bypass the router.' \
        'For tailnet access, use Grants for approved clients and the verified TCP port. Review overlapping grants and ACLs.' \
        'Check effective firewall order. Tailscale can accept tailscale0 traffic before other firewall rules.'
}

promptRule() {
    command_exists ss python3 || fail "Applying a rule requires ss and python3."
    printf '\n%s' 'Enter an SSH port verified in the listener list (Enter to finish the audit) '
    IFS= read -r SSH_PORT || exit 0
    [ -n "$SSH_PORT" ] || exit 0
    case "$SSH_PORT" in
        *[!0-9]*|0*|??????*) fail "Enter an SSH port from 1 to 65535." ;;
    esac
    [ "$SSH_PORT" -le 65535 ] || fail "Enter an SSH port from 1 to 65535."

    listeners=$(ss -H -ltn "sport = :$SSH_PORT") || fail "Could not verify the selected listener."
    [ -n "$listeners" ] || fail "No TCP listener found on port $SSH_PORT."
    printf '%s\n' "$listeners"

    printf '%s' 'Trusted admin IP address or network in CIDR notation '
    IFS= read -r source_input || exit 0
    source=$(
        python3 - "$source_input" <<'PY'
import ipaddress
import sys

entry = sys.argv[1]
try:
    network = ipaddress.ip_network(entry)
except ValueError:
    sys.exit("Enter an IP address or a network with a valid prefix and no host bits.")
if (
    "%" in entry
    or network.prefixlen == 0
    or network.network_address.is_unspecified
    or network.network_address.is_multicast
):
    sys.exit("Enter a trusted unicast address or a specific network without a zone suffix.")
print(f"ipv{network.version} {network}")
PY
    ) || exit 1
    SOURCE_FAMILY=${source%% *}
    SOURCE_NETWORK=${source#* }

    if [ "$FIREWALLD_ACTIVE" = yes ]; then
        printf '%s' 'Active firewalld zone that receives this source '
        IFS= read -r FIREWALL_ZONE || exit 0
        case "$FIREWALL_ZONE" in
            ""|*[!A-Za-z0-9_-]*) fail "Enter a zone from the audit." ;;
        esac
        checkFirewalldZone
        RICH_RULE="rule family=\"$SOURCE_FAMILY\" source address=\"$SOURCE_NETWORK\" port port=\"$SSH_PORT\" protocol=\"tcp\" accept"
        RULE_SCOPE="firewalld zone $FIREWALL_ZONE"
    else
        command_exists ip || fail "Applying a UFW rule requires ip."
        printf '%s' 'Inbound interface that receives this source '
        IFS= read -r INGRESS_INTERFACE || exit 0
        case "$INGRESS_INTERFACE" in
            ""|-*|*[!A-Za-z0-9_.:-]*) fail "Enter the name of a local network interface." ;;
        esac
        ip link show dev "$INGRESS_INTERFACE" >/dev/null || fail "The selected interface does not exist."
        if [ "$SOURCE_FAMILY" = ipv6 ] && grep -Eq '^[[:space:]]*IPV6=no([[:space:]]|$)' /etc/default/ufw 2>/dev/null; then
            fail "UFW IPv6 rule handling is disabled. Review UFW before adding an IPv6 source."
        fi
        RULE_SCOPE="UFW interface $INGRESS_INTERFACE"
    fi

    printf '\n%s\n' "Allow TCP $SSH_PORT from $SOURCE_NETWORK on $RULE_SCOPE." \
        'Keep your working SSH session and recovery console open. Save the current rules before applying.' \
        'Test a fresh connection from the approved source, then check broader legacy rules before retiring them.'
    printf '%s' 'Type APPLY to add this rule '
    IFS= read -r answer || exit 0
    [ "$answer" = APPLY ] || exit 0
}

checkFirewalldZone() {
    active_zones=$("$ESCALATION_TOOL" firewall-cmd --get-active-zones)
    printf '%s\n' "$active_zones" |
        awk -v zone="$FIREWALL_ZONE" '/^[^[:space:]]/ && $1 == zone { found = 1 } END { exit !found }' ||
        fail "The selected firewalld zone is not active."
}

firewalldRule() {
    "$ESCALATION_TOOL" firewall-cmd --zone="$FIREWALL_ZONE" "$@"
}

firewalldRuleState() {
    if result=$(firewalldRule "$@" --query-rich-rule="$RICH_RULE"); then
        [ "$result" = yes ] || return 2
    else
        [ "$?" -eq 1 ] && [ "$result" = no ] || return 2
    fi
    printf '%s\n' "$result"
}

printFirewalldRollback() {
    printf "%s firewall-cmd --zone=%s %s--remove-rich-rule='%s'\n" \
        "$ESCALATION_TOOL" "$FIREWALL_ZONE" "$1" "$RICH_RULE"
}

applyFirewalld() {
    runtime_rule=$(firewalldRuleState) || fail "Could not verify existing runtime rules."
    permanent_rule=$(firewalldRuleState --permanent) || fail "Could not verify existing permanent rules."

    if [ "$runtime_rule" = no ]; then
        firewalldRule --add-rich-rule="$RICH_RULE"
    fi
    if [ "$permanent_rule" = no ]; then
        if ! firewalldRule --permanent --add-rich-rule="$RICH_RULE"; then
            if [ "$runtime_rule" = no ] && ! firewalldRule --remove-rich-rule="$RICH_RULE"; then
                printf '%s\n' 'The runtime rule could not be rolled back. Use the recovery console.'
                printFirewalldRollback ""
            fi
            fail "Could not add the permanent rule."
        fi
    fi

    if [ "$runtime_rule" = no ] || [ "$permanent_rule" = no ]; then
        printf '%s\n' 'Commands to roll back this change from the recovery console'
        if [ "$runtime_rule" = no ]; then
            printFirewalldRollback ""
        fi
        if [ "$permanent_rule" = no ]; then
            printFirewalldRollback "--permanent "
        fi
    else
        printf '%s\n' 'The exact SSH rule is already present at runtime and on disk.'
    fi
    [ "$(firewalldRuleState)" = yes ] && [ "$(firewalldRuleState --permanent)" = yes ] ||
        fail "Could not verify the rule at runtime and on disk."
}

applyUfw() {
    # UFW can replace the action, logging, or comment on an exact match.
    added_rules=$("$ESCALATION_TOOL" ufw show added) || fail "Could not check existing UFW rules."
    matching_actions=$(printf '%s\n' "$added_rules" |
        awk -v interface="$INGRESS_INTERFACE" -v source="$SOURCE_NETWORK" -v port="$SSH_PORT" '
            BEGIN {
                host = source
                if (index(source, ":")) sub("/128$", "", host)
                else sub("/32$", "", host)
            }
            $1 == "ufw" && $3 == "in" && $4 == "on" && $5 == interface {
                first = 6
                if ($first == "log" || $first == "log-all") first++
                if ($first == "from" && ($(first+1) == source || $(first+1) == host) &&
                    $(first+2) == "to" && $(first+3) == "any" && $(first+4) == "port" &&
                    $(first+5) == port && $(first+6) == "proto" && $(first+7) == "tcp") print $2
            }
        ')
    case "$matching_actions" in
        allow)
            printf '%s\n' 'The exact UFW allow rule is already present.'
            return 0
            ;;
        "") ;;
        *) fail "UFW already has a rule for this scope. Review it before changing its action." ;;
    esac

    result=$("$ESCALATION_TOOL" ufw allow in on "$INGRESS_INTERFACE" proto tcp \
        from "$SOURCE_NETWORK" to any port "$SSH_PORT") || fail "UFW could not apply the SSH rule."
    printf '%s\n' "$result"
    case "$result" in
        *'Rule added'*)
            printf '%s\n' 'Command to roll back this change from the recovery console'
            printf '%s ufw delete allow in on %s proto tcp from %s to any port %s\n' \
                "$ESCALATION_TOOL" "$INGRESS_INTERFACE" "$SOURCE_NETWORK" "$SSH_PORT"
            ;;
        *'Skipping adding existing rule'*) ;;
        *) fail "UFW did not report a new rule. Review the active rules before testing SSH." ;;
    esac
    "$ESCALATION_TOOL" ufw status verbose
}

case "$*" in
    ""|--audit) ;;
    *) fail "Usage: $0 [--audit]" ;;
esac

checkEscalationTool
detectBackends
auditFirewall
[ "$#" -eq 0 ] || exit 0

[ -t 0 ] || fail "Run the firewall setup in a terminal so you can select the SSH port and trusted source."

if [ "$FIREWALLD_ACTIVE" = "$UFW_ACTIVE" ]; then
    printf '\n%s\n' 'Applying a rule requires a single active firewalld or UFW backend.'
    exit 0
fi

promptRule
previous_backends="$FIREWALLD_ACTIVE:$UFW_ACTIVE"
detectBackends
[ "$previous_backends" = "$FIREWALLD_ACTIVE:$UFW_ACTIVE" ] || fail "Firewall status changed. Run the audit again."
if [ "$FIREWALLD_ACTIVE" = yes ]; then
    checkFirewalldZone
    applyFirewalld
else
    applyUfw
fi

printf '\n%s\n' 'Verify the SSH connection and check that unapproved LAN, WAN, and tailnet sources are blocked.'
