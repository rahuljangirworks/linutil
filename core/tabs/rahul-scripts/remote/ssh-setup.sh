#!/bin/sh -e

# Description: Install and securely configure OpenSSH server
# Rerunnable: Yes - skips completed steps

. ../../common-script.sh

SSHD_CONFIG="/etc/ssh/sshd_config"
BACKUP_FILE="/etc/ssh/sshd_config.bak.linutil"

# Helper to check if a config option is already set
configHasValue() {
    option="$1"
    value="$2"
    grep -qE "^${option}[[:space:]]+${value}" "$SSHD_CONFIG" 2>/dev/null
}

# Helper to set a config option (idempotent)
setConfig() {
    option="$1"
    value="$2"
    
    if configHasValue "$option" "$value"; then
        printf "%b\n" "${GREEN}✓ $option already set to $value${RC}"
        return 0
    fi
    
    # Check if option exists (commented or uncommented)
    if grep -qE "^#?${option}" "$SSHD_CONFIG"; then
        # Replace existing line
        # Note: avoid using "$ESCALATION_TOOL" with sed when ESCALATION_TOOL=eval
        # because eval re-parses and word-splits the sed expression
        if [ "$(id -u)" = "0" ]; then
            sed -i "s/^#*${option}.*/${option} ${value}/" "$SSHD_CONFIG"
        else
            "$ESCALATION_TOOL" sed -i "s/^#*${option}.*/${option} ${value}/" "$SSHD_CONFIG"
        fi
    else
        # Append new option
        printf '%s %s\n' "$option" "$value" | "$ESCALATION_TOOL" tee -a "$SSHD_CONFIG" > /dev/null
    fi
    printf "%b\n" "${YELLOW}→ Set $option to $value${RC}"
}

installSSH() {
    # Check if already installed
    if command -v sshd >/dev/null 2>&1; then
        printf "%b\n" "${GREEN}✓ OpenSSH server already installed${RC}"
        return 0
    fi
    
    printf "%b\n" "${YELLOW}Installing OpenSSH server...${RC}"
    
    case "$PACKAGER" in
        pacman)
            "$ESCALATION_TOOL" "$PACKAGER" -S --needed --noconfirm openssh
            ;;
        apt-get|nala)
            "$ESCALATION_TOOL" "$PACKAGER" update
            "$ESCALATION_TOOL" "$PACKAGER" install -y openssh-server
            ;;
        dnf|yum)
            "$ESCALATION_TOOL" "$PACKAGER" install -y openssh-server
            ;;
        zypper)
            "$ESCALATION_TOOL" "$PACKAGER" install -y openssh
            ;;
        *)
            printf "%b\n" "${RED}Unsupported package manager: $PACKAGER${RC}"
            exit 1
            ;;
    esac
    
    printf "%b\n" "${GREEN}✓ OpenSSH server installed${RC}"
}

backupConfig() {
    if [ -f "$BACKUP_FILE" ]; then
        printf "%b\n" "${GREEN}✓ Backup already exists at $BACKUP_FILE${RC}"
        return 0
    fi
    
    if [ -f "$SSHD_CONFIG" ]; then
        "$ESCALATION_TOOL" cp "$SSHD_CONFIG" "$BACKUP_FILE"
        printf "%b\n" "${GREEN}✓ Created backup at $BACKUP_FILE${RC}"
    fi
}

hardenSSH() {
    printf "%b\n" "${CYAN}========================================${RC}"
    printf "%b\n" "${CYAN}Applying SSH Security Hardening${RC}"
    printf "%b\n" "${CYAN}========================================${RC}"
    
    # Disable root login
    setConfig "PermitRootLogin" "no"
    
    # Disable empty passwords
    setConfig "PermitEmptyPasswords" "no"
    
    # Limit authentication attempts
    setConfig "MaxAuthTries" "3"
    
    # Set idle timeout (5 min interval, 2 retries = 10 min max idle)
    setConfig "ClientAliveInterval" "300"
    setConfig "ClientAliveCountMax" "2"
    
    # Disable X11 forwarding (security risk if not needed)
    setConfig "X11Forwarding" "no"
    
    # Disable host-based authentication
    setConfig "HostbasedAuthentication" "no"
    setConfig "IgnoreRhosts" "yes"
    
    # Keep password auth enabled (user preference)
    setConfig "PasswordAuthentication" "yes"
    
    printf "%b\n" "${GREEN}✓ SSH hardening complete${RC}"
}

validateConfig() {
    printf "%b\n" "${YELLOW}Validating SSH configuration...${RC}"
    
    if "$ESCALATION_TOOL" sshd -t 2>/dev/null; then
        printf "%b\n" "${GREEN}✓ Configuration is valid${RC}"
        return 0
    else
        printf "%b\n" "${RED}✗ Configuration has errors! Restoring backup...${RC}"
        if [ -f "$BACKUP_FILE" ]; then
            "$ESCALATION_TOOL" cp "$BACKUP_FILE" "$SSHD_CONFIG"
            printf "%b\n" "${YELLOW}Backup restored${RC}"
        fi
        exit 1
    fi
}

enableSSH() {
    # Check if already enabled and running
    if systemctl is-active --quiet sshd 2>/dev/null || systemctl is-active --quiet ssh 2>/dev/null; then
        printf "%b\n" "${GREEN}✓ SSH service already running${RC}"
        # Reload to apply any config changes
        "$ESCALATION_TOOL" systemctl reload sshd 2>/dev/null || "$ESCALATION_TOOL" systemctl reload ssh 2>/dev/null || true
        printf "%b\n" "${GREEN}✓ SSH config reloaded${RC}"
        return 0
    fi
    
    printf "%b\n" "${YELLOW}Enabling and starting SSH service...${RC}"
    
    # Try sshd first (Arch, Fedora), then ssh (Debian/Ubuntu)
    if "$ESCALATION_TOOL" systemctl enable --now sshd 2>/dev/null; then
        printf "%b\n" "${GREEN}✓ SSH service (sshd) enabled and started${RC}"
    elif "$ESCALATION_TOOL" systemctl enable --now ssh 2>/dev/null; then
        printf "%b\n" "${GREEN}✓ SSH service (ssh) enabled and started${RC}"
    else
        printf "%b\n" "${RED}Failed to enable SSH service${RC}"
        exit 1
    fi
}

printStatus() {
    printf "%b\n" "${GREEN}========================================${RC}"
    printf "%b\n" "${GREEN}SSH Setup Complete!${RC}"
    printf "%b\n" "${GREEN}========================================${RC}"
    
    # Get IP address
    IP_ADDR=$(hostname -I 2>/dev/null | awk '{print $1}' || echo "your-ip")
    
    printf "%b\n" "${CYAN}Connect with: ssh $(whoami)@${IP_ADDR}${RC}"
    printf "%b\n" "${CYAN}${RC}"
    printf "%b\n" "${CYAN}Security settings applied:${RC}"
    printf "%b\n" "${CYAN}  • Root login disabled${RC}"
    printf "%b\n" "${CYAN}  • Empty passwords disabled${RC}"
    printf "%b\n" "${CYAN}  • Max 3 auth attempts${RC}"
    printf "%b\n" "${CYAN}  • 10 min idle timeout${RC}"
    printf "%b\n" "${CYAN}  • X11 forwarding disabled${RC}"
    printf "%b\n" "${CYAN}  • Password auth enabled${RC}"
    printf "%b\n" "${GREEN}========================================${RC}"
}

# Main execution
checkEnv
checkEscalationTool
installSSH
backupConfig
hardenSSH
validateConfig
enableSSH
printStatus
