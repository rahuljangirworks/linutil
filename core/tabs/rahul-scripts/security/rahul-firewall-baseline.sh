#!/bin/sh -e

# Description: Configure a safe host firewall baseline aligned with Rahul's SSH hardening.
# Rerunnable: Yes - detects SSH port, avoids duplicate managers, and uses idempotent rules.

. ../../common-script.sh

SSH_PORT="22"
FIREWALL_BACKEND=""
FIREWALL_ZONE="public"
OPEN_WEB_PORTS="no"

detectSSHPort() {
    if command -v sshd > /dev/null 2>&1; then
        detected_port=$("$ESCALATION_TOOL" sshd -T 2>/dev/null | awk '$1 == "port" { print $2; exit }' || true)
        if [ -n "$detected_port" ]; then
            SSH_PORT="$detected_port"
            printf "%b\n" "${GREEN}✓ Detected SSH port from sshd: $SSH_PORT${RC}"
            return 0
        fi
    fi

    for config in /etc/ssh/sshd_config.d/00-hardening.conf /etc/ssh/sshd_config; do
        if [ -r "$config" ]; then
            detected_port=$(awk '$1 == "Port" { print $2; exit }' "$config" 2>/dev/null || true)
            if [ -n "$detected_port" ]; then
                SSH_PORT="$detected_port"
                printf "%b\n" "${GREEN}✓ Detected SSH port from $config: $SSH_PORT${RC}"
                return 0
            fi
        fi
    done

    printf "%b\n" "${YELLOW}→ Could not detect SSH port, using 22${RC}"
}

askWebPorts() {
    printf "%b" "${YELLOW}Open HTTP/HTTPS ports for a web server? [y/N]: ${RC}"
    read -r web_choice
    case "$web_choice" in
        y|Y|yes|YES)
            OPEN_WEB_PORTS="yes"
            ;;
        *)
            OPEN_WEB_PORTS="no"
            ;;
    esac
}

installFirewalld() {
    if command_exists firewall-cmd; then
        return 0
    fi

    printf "%b\n" "${YELLOW}Installing firewalld...${RC}"
    case "$PACKAGER" in
        pacman)
            "$ESCALATION_TOOL" "$PACKAGER" -S --needed --noconfirm firewalld
            ;;
        apt-get|nala)
            "$ESCALATION_TOOL" "$PACKAGER" update
            "$ESCALATION_TOOL" "$PACKAGER" install -y firewalld
            ;;
        dnf|yum|zypper)
            "$ESCALATION_TOOL" "$PACKAGER" install -y firewalld
            ;;
        *)
            return 1
            ;;
    esac
}

installUfw() {
    if command_exists ufw; then
        return 0
    fi

    printf "%b\n" "${YELLOW}Installing UFW...${RC}"
    case "$PACKAGER" in
        pacman)
            "$ESCALATION_TOOL" "$PACKAGER" -S --needed --noconfirm ufw
            ;;
        apk)
            "$ESCALATION_TOOL" "$PACKAGER" add ufw
            ;;
        xbps-install)
            "$ESCALATION_TOOL" "$PACKAGER" -Sy ufw
            ;;
        apt-get|nala)
            "$ESCALATION_TOOL" "$PACKAGER" update
            "$ESCALATION_TOOL" "$PACKAGER" install -y ufw
            ;;
        dnf|yum|zypper)
            "$ESCALATION_TOOL" "$PACKAGER" install -y ufw
            ;;
        *)
            return 1
            ;;
    esac
}

chooseFirewallBackend() {
    if command_exists firewall-cmd && firewall-cmd --state > /dev/null 2>&1; then
        FIREWALL_BACKEND="firewalld"
        return 0
    fi

    if command_exists ufw && ufw status 2>/dev/null | grep -q "Status: active"; then
        FIREWALL_BACKEND="ufw"
        return 0
    fi

    case "$PACKAGER" in
        dnf|yum|zypper|pacman)
            installFirewalld && FIREWALL_BACKEND="firewalld" && return 0
            ;;
        *)
            installUfw && FIREWALL_BACKEND="ufw" && return 0
            ;;
    esac

    if installFirewalld; then
        FIREWALL_BACKEND="firewalld"
    elif installUfw; then
        FIREWALL_BACKEND="ufw"
    else
        printf "%b\n" "${RED}✗ Could not install firewalld or ufw for this system.${RC}"
        exit 1
    fi
}

configureFirewalld() {
    printf "%b\n" "${YELLOW}Configuring firewalld baseline...${RC}"

    "$ESCALATION_TOOL" systemctl enable --now firewalld

    FIREWALL_ZONE=$(firewall-cmd --get-default-zone 2>/dev/null || printf "public")
    FIREWALL_ZONE="${FIREWALL_ZONE:-public}"
    printf "%b\n" "${CYAN}Using firewalld zone: $FIREWALL_ZONE${RC}"

    if [ "$SSH_PORT" = "22" ]; then
        "$ESCALATION_TOOL" firewall-cmd --permanent --zone="$FIREWALL_ZONE" --add-service=ssh
        printf "%b\n" "${GREEN}✓ Allowed SSH service on port 22${RC}"
    else
        "$ESCALATION_TOOL" firewall-cmd --permanent --zone="$FIREWALL_ZONE" --remove-service=ssh 2>/dev/null || true
        "$ESCALATION_TOOL" firewall-cmd --permanent --zone="$FIREWALL_ZONE" --add-port="${SSH_PORT}/tcp"
        printf "%b\n" "${GREEN}✓ Allowed SSH custom port ${SSH_PORT}/tcp${RC}"
    fi

    if [ "$OPEN_WEB_PORTS" = "yes" ]; then
        "$ESCALATION_TOOL" firewall-cmd --permanent --zone="$FIREWALL_ZONE" --add-service=http
        "$ESCALATION_TOOL" firewall-cmd --permanent --zone="$FIREWALL_ZONE" --add-service=https
        printf "%b\n" "${GREEN}✓ Allowed HTTP/HTTPS services${RC}"
    else
        printf "%b\n" "${CYAN}→ HTTP/HTTPS left unchanged${RC}"
    fi

    "$ESCALATION_TOOL" firewall-cmd --reload
    printf "%b\n" "${GREEN}✓ firewalld baseline applied${RC}"
}

configureUfw() {
    printf "%b\n" "${YELLOW}Configuring UFW baseline...${RC}"

    if command_exists firewall-cmd && firewall-cmd --state > /dev/null 2>&1; then
        printf "%b\n" "${RED}✗ firewalld is active. Refusing to enable UFW at the same time.${RC}"
        printf "%b\n" "${CYAN}  Use the firewalld backend or disable firewalld manually first.${RC}"
        exit 1
    fi

    "$ESCALATION_TOOL" ufw default deny incoming
    "$ESCALATION_TOOL" ufw default allow outgoing
    "$ESCALATION_TOOL" ufw limit "${SSH_PORT}/tcp"
    printf "%b\n" "${GREEN}✓ Limited SSH on ${SSH_PORT}/tcp${RC}"

    if [ "$OPEN_WEB_PORTS" = "yes" ]; then
        "$ESCALATION_TOOL" ufw allow 80/tcp
        "$ESCALATION_TOOL" ufw allow 443/tcp
        printf "%b\n" "${GREEN}✓ Allowed HTTP/HTTPS ports${RC}"
    else
        printf "%b\n" "${CYAN}→ HTTP/HTTPS not opened${RC}"
    fi

    "$ESCALATION_TOOL" ufw --force enable
    printf "%b\n" "${GREEN}✓ UFW baseline applied${RC}"
}

printSummary() {
    printf "%b\n" "${GREEN}========================================${RC}"
    printf "%b\n" "${GREEN}  Rahul Firewall Baseline Complete${RC}"
    printf "%b\n" "${GREEN}========================================${RC}"
    printf "%b\n" "${CYAN}  Backend       : $FIREWALL_BACKEND${RC}"
    printf "%b\n" "${CYAN}  SSH port      : ${SSH_PORT}/tcp${RC}"
    printf "%b\n" "${CYAN}  HTTP/HTTPS    : $OPEN_WEB_PORTS${RC}"
    if [ "$FIREWALL_BACKEND" = "firewalld" ]; then
        printf "%b\n" "${CYAN}  Zone          : $FIREWALL_ZONE${RC}"
        firewall-cmd --zone="$FIREWALL_ZONE" --list-all 2>/dev/null || true
    else
        "$ESCALATION_TOOL" ufw status verbose 2>/dev/null || true
    fi
    printf "%b\n" "${GREEN}========================================${RC}"
}

checkEnv
checkEscalationTool
detectSSHPort
askWebPorts
chooseFirewallBackend

case "$FIREWALL_BACKEND" in
    firewalld)
        configureFirewalld
        ;;
    ufw)
        configureUfw
        ;;
    *)
        printf "%b\n" "${RED}Unsupported firewall backend: $FIREWALL_BACKEND${RC}"
        exit 1
        ;;
esac

printSummary
