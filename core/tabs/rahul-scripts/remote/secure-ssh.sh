#!/bin/sh -e

# Description: Comprehensive SSH hardening with strong crypto, Ed25519 keys, drop-in config, and post-quantum KEX
# Rerunnable: Yes - backs up config, validates before applying, auto-rollback on error
# Author: Rahul Jangir
# Based on: https://github.com/rahuljangirworks/secure-SSH

. ../../common-script.sh

# ─── Constants ──────────────────────────────────────────────────────────────
SSHD_CONFIG="/etc/ssh/sshd_config"
SSHD_HARDENING_CONF="/etc/ssh/sshd_config.d/00-hardening.conf"
BACKUP_DIR="/etc/ssh/backups"
SSH_PORT="22"

# ─── Recommended Crypto Settings ───────────────────────────────────────────
# Post-quantum ready (OpenSSH 10+)
PQ_KEX="mlkem768x25519-sha256,sntrup761x25519-sha512@openssh.com,curve25519-sha256,curve25519-sha256@libssh.org,diffie-hellman-group16-sha512,diffie-hellman-group18-sha512"
# Classical with sntrup761 (OpenSSH 9.x)
CLASSIC_KEX="sntrup761x25519-sha512@openssh.com,curve25519-sha256,curve25519-sha256@libssh.org,diffie-hellman-group16-sha512,diffie-hellman-group18-sha512"
# Fallback for older versions
LEGACY_KEX="curve25519-sha256,curve25519-sha256@libssh.org,diffie-hellman-group16-sha512,diffie-hellman-group14-sha256"

RECOMMENDED_CIPHERS="chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com,aes256-ctr,aes192-ctr,aes128-ctr"
RECOMMENDED_MACS="hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com,umac-128-etm@openssh.com"
RECOMMENDED_HOST_KEY_ALGOS="ssh-ed25519-cert-v01@openssh.com,ssh-ed25519,rsa-sha2-512-cert-v01@openssh.com,rsa-sha2-512,rsa-sha2-256-cert-v01@openssh.com,rsa-sha2-256"

# ─── Prompt for SSH port ───────────────────────────────────────────────────
askSSHPort() {
    CURRENT_PORT=$(grep -E "^#?Port " "$SSHD_CONFIG" 2>/dev/null | head -1 | awk '{print $2}' || echo "22")
    CURRENT_PORT="${CURRENT_PORT:-22}"

    printf "%b\n" "${CYAN}========================================${RC}"
    printf "%b\n" "${CYAN}SSH Port Configuration${RC}"
    printf "%b\n" "${CYAN}========================================${RC}"
    printf "%b" "${CYAN}Enter SSH port [${CURRENT_PORT}]: ${RC}"
    read -r INPUT_PORT
    SSH_PORT="${INPUT_PORT:-$CURRENT_PORT}"

    if [ "$SSH_PORT" != "$CURRENT_PORT" ]; then
        printf "%b\n" "${YELLOW}⚠ SSH port will change from ${CURRENT_PORT} to ${SSH_PORT}${RC}"
        printf "%b\n" "${YELLOW}  Make sure to update your firewall and connection settings!${RC}"
    else
        printf "%b\n" "${GREEN}✓ Using SSH port: ${SSH_PORT}${RC}"
    fi
}

# ─── Detect OpenSSH Version ────────────────────────────────────────────────
detectOpenSSHVersion() {
    OPENSSH_MAJOR=0
    OPENSSH_MINOR=0

    if command -v sshd > /dev/null 2>&1; then
        OPENSSH_VERSION=$(sshd -V 2>&1 | sed -n 's/.*OpenSSH_\([0-9]*\.[0-9]*\).*/\1/p' | head -1)
        OPENSSH_VERSION="${OPENSSH_VERSION:-unknown}"
        if [ "$OPENSSH_VERSION" != "unknown" ]; then
            OPENSSH_MAJOR=$(echo "$OPENSSH_VERSION" | cut -d. -f1)
            OPENSSH_MINOR=$(echo "$OPENSSH_VERSION" | cut -d. -f2)
            printf "%b\n" "${GREEN}✓ OpenSSH version: ${OPENSSH_VERSION}${RC}"
        else
            printf "%b\n" "${YELLOW}⚠ Could not detect OpenSSH version, using safe defaults${RC}"
        fi
    fi
}

# ─── Select KEX algorithms based on OpenSSH version ────────────────────────
selectKEX() {
    if [ "$OPENSSH_MAJOR" -ge 10 ] 2>/dev/null; then
        KEX_ALGORITHMS="$PQ_KEX"
        printf "%b\n" "${GREEN}✓ Post-quantum KEX: enabled (OpenSSH 10+)${RC}"
    elif [ "$OPENSSH_MAJOR" -ge 9 ] 2>/dev/null; then
        KEX_ALGORITHMS="$CLASSIC_KEX"
        printf "%b\n" "${CYAN}→ Post-quantum KEX: partial (sntrup761, OpenSSH 9.x)${RC}"
    else
        KEX_ALGORITHMS="$LEGACY_KEX"
        printf "%b\n" "${CYAN}→ Post-quantum KEX: not available, using classical${RC}"
    fi
}

# ─── Install OpenSSH server if missing ─────────────────────────────────────
installSSH() {
    if command -v sshd > /dev/null 2>&1; then
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
            printf "%b\n" "${RED}✗ Unsupported package manager: $PACKAGER${RC}"
            exit 1
            ;;
    esac

    printf "%b\n" "${GREEN}✓ OpenSSH server installed${RC}"
}

# ─── Create backup ─────────────────────────────────────────────────────────
createBackup() {
    printf "%b\n" "${CYAN}========================================${RC}"
    printf "%b\n" "${CYAN}Creating SSH Config Backup${RC}"
    printf "%b\n" "${CYAN}========================================${RC}"

    TIMESTAMP=$(date '+%Y%m%d_%H%M%S')
    "$ESCALATION_TOOL" mkdir -p "$BACKUP_DIR"

    if [ -f "$SSHD_CONFIG" ]; then
        "$ESCALATION_TOOL" cp "$SSHD_CONFIG" "${BACKUP_DIR}/sshd_config.${TIMESTAMP}"
        printf "%b\n" "${GREEN}✓ Backed up: ${SSHD_CONFIG}${RC}"
    fi

    if [ -f "$SSHD_HARDENING_CONF" ]; then
        "$ESCALATION_TOOL" cp "$SSHD_HARDENING_CONF" "${BACKUP_DIR}/00-hardening.conf.${TIMESTAMP}"
        printf "%b\n" "${GREEN}✓ Backed up existing hardening config${RC}"
    fi

    echo "$TIMESTAMP" | "$ESCALATION_TOOL" tee "${BACKUP_DIR}/.latest" > /dev/null
}

# ─── Ensure drop-in config directory ───────────────────────────────────────
ensureDropInDir() {
    if [ ! -d "/etc/ssh/sshd_config.d" ]; then
        "$ESCALATION_TOOL" mkdir -p /etc/ssh/sshd_config.d
        printf "%b\n" "${CYAN}→ Created /etc/ssh/sshd_config.d/${RC}"
    fi

    # Ensure Include directive exists in main config
    if ! grep -q "^Include /etc/ssh/sshd_config.d/" "$SSHD_CONFIG" 2>/dev/null; then
        # Avoid eval word-splitting by checking if root
        if [ "$(id -u)" = "0" ]; then
            sed -i '1s|^|Include /etc/ssh/sshd_config.d/*.conf\n|' "$SSHD_CONFIG"
        else
            "$ESCALATION_TOOL" sed -i '1s|^|Include /etc/ssh/sshd_config.d/*.conf\n|' "$SSHD_CONFIG"
        fi
        printf "%b\n" "${CYAN}→ Added Include directive to sshd_config${RC}"
    else
        printf "%b\n" "${GREEN}✓ Include directive already present${RC}"
    fi
}

# ─── Generate Ed25519 host key if missing ──────────────────────────────────
ensureHostKeys() {
    if [ ! -f /etc/ssh/ssh_host_ed25519_key ]; then
        printf "%b\n" "${YELLOW}→ Generating Ed25519 host key...${RC}"
        "$ESCALATION_TOOL" ssh-keygen -t ed25519 -f /etc/ssh/ssh_host_ed25519_key -N "" -q
        printf "%b\n" "${GREEN}✓ Ed25519 host key generated${RC}"
    else
        printf "%b\n" "${GREEN}✓ Ed25519 host key exists${RC}"
    fi

    # Remove weak DSA key if present
    if [ -f /etc/ssh/ssh_host_dsa_key ]; then
        "$ESCALATION_TOOL" mv /etc/ssh/ssh_host_dsa_key /etc/ssh/ssh_host_dsa_key.disabled
        "$ESCALATION_TOOL" mv /etc/ssh/ssh_host_dsa_key.pub /etc/ssh/ssh_host_dsa_key.pub.disabled 2>/dev/null || true
        printf "%b\n" "${YELLOW}→ Disabled insecure DSA host key${RC}"
    fi
}

# ─── Create SSH warning banner ─────────────────────────────────────────────
createBanner() {
    if [ -f /etc/ssh/banner ]; then
        printf "%b\n" "${GREEN}✓ SSH banner already exists${RC}"
        return 0
    fi

    "$ESCALATION_TOOL" tee /etc/ssh/banner > /dev/null << 'BANNEREOF'
╔══════════════════════════════════════════════════════════════════╗
║                    AUTHORIZED ACCESS ONLY                       ║
║                                                                  ║
║  This system is for authorized users only. All activity is       ║
║  monitored and logged. Unauthorized access will be prosecuted    ║
║  to the fullest extent of the law.                               ║
║                                                                  ║
║  By proceeding, you agree to the terms of use.                   ║
╚══════════════════════════════════════════════════════════════════╝
BANNEREOF

    "$ESCALATION_TOOL" chmod 644 /etc/ssh/banner
    printf "%b\n" "${GREEN}✓ SSH banner created${RC}"
}

# ─── Write hardening drop-in config ────────────────────────────────────────
writeHardeningConfig() {
    printf "%b\n" "${CYAN}========================================${RC}"
    printf "%b\n" "${CYAN}Writing SSH Hardening Configuration${RC}"
    printf "%b\n" "${CYAN}========================================${RC}"

    "$ESCALATION_TOOL" tee "$SSHD_HARDENING_CONF" > /dev/null << SSHEOF
# ============================================================================
#  SSH Hardening Configuration
#  Generated by Linutil SSH Hardening on $(date '+%Y-%m-%d %H:%M:%S')
#  DO NOT EDIT — managed by linutil rahul-ssh-hardening.sh
# ============================================================================

# ─── Port & Protocol ───────────────────────────────────────────────────────
Port ${SSH_PORT}
Protocol 2
AddressFamily inet

# ─── Authentication ────────────────────────────────────────────────────────
PubkeyAuthentication yes
PasswordAuthentication no
PermitRootLogin no
PermitEmptyPasswords no
MaxAuthTries 3
LoginGraceTime 30
AuthenticationMethods publickey
StrictModes yes

# ─── Cryptography ──────────────────────────────────────────────────────────
HostKey /etc/ssh/ssh_host_ed25519_key
HostKey /etc/ssh/ssh_host_rsa_key
HostKeyAlgorithms ${RECOMMENDED_HOST_KEY_ALGOS}
KexAlgorithms ${KEX_ALGORITHMS}
Ciphers ${RECOMMENDED_CIPHERS}
MACs ${RECOMMENDED_MACS}

# ─── Session Security ──────────────────────────────────────────────────────
ClientAliveInterval 300
ClientAliveCountMax 2
MaxSessions 3
X11Forwarding no
AllowAgentForwarding no
AllowTcpForwarding no
PermitTunnel no
GatewayPorts no
PermitUserEnvironment no

# ─── Logging ───────────────────────────────────────────────────────────────
LogLevel VERBOSE
SyslogFacility AUTH

# ─── Legacy & Compatibility ────────────────────────────────────────────────
HostbasedAuthentication no
IgnoreRhosts yes
UsePAM yes

# ─── Banner ────────────────────────────────────────────────────────────────
Banner /etc/ssh/banner
PrintMotd no
PrintLastLog yes

# ─── Challenge-Response ────────────────────────────────────────────────────
ChallengeResponseAuthentication no
KbdInteractiveAuthentication no
SSHEOF

    "$ESCALATION_TOOL" chmod 600 "$SSHD_HARDENING_CONF"
    printf "%b\n" "${GREEN}✓ Hardening config written: ${SSHD_HARDENING_CONF}${RC}"
}

# ─── Set file permissions ──────────────────────────────────────────────────
securePermissions() {
    "$ESCALATION_TOOL" chmod 600 /etc/ssh/ssh_host_*_key 2>/dev/null || true
    "$ESCALATION_TOOL" chmod 644 /etc/ssh/ssh_host_*_key.pub 2>/dev/null || true
    printf "%b\n" "${GREEN}✓ SSH file permissions secured${RC}"
}

# ─── Validate config ──────────────────────────────────────────────────────
validateConfig() {
    printf "%b\n" "${YELLOW}Validating SSH configuration...${RC}"

    # Run sshd -t and capture errors for debugging
    if [ "$(id -u)" = "0" ]; then
        SSHD_ERRORS=$(sshd -t 2>&1) && SSHD_VALID=0 || SSHD_VALID=1
    else
        SSHD_ERRORS=$("$ESCALATION_TOOL" sshd -t 2>&1) && SSHD_VALID=0 || SSHD_VALID=1
    fi

    if [ "$SSHD_VALID" = "0" ]; then
        printf "%b\n" "${GREEN}✓ Configuration is valid${RC}"
        return 0
    else
        printf "%b\n" "${RED}✗ Configuration has syntax errors!${RC}"
        printf "%b\n" "${RED}  Error: ${SSHD_ERRORS}${RC}"
        printf "%b\n" "${YELLOW}Reverting hardening config...${RC}"
        if [ "$(id -u)" = "0" ]; then
            rm -f "$SSHD_HARDENING_CONF"
        else
            "$ESCALATION_TOOL" rm -f "$SSHD_HARDENING_CONF"
        fi
        # Restore from latest backup if available
        if [ -f "${BACKUP_DIR}/.latest" ]; then
            LATEST_TS=$(cat "${BACKUP_DIR}/.latest")
            if [ -f "${BACKUP_DIR}/sshd_config.${LATEST_TS}" ]; then
                "$ESCALATION_TOOL" cp "${BACKUP_DIR}/sshd_config.${LATEST_TS}" "$SSHD_CONFIG"
                printf "%b\n" "${YELLOW}→ Restored backup from ${LATEST_TS}${RC}"
            fi
        fi
        printf "%b\n" "${RED}Please check SSH configuration and try again${RC}"
        exit 1
    fi
}

# ─── Restart SSH service ──────────────────────────────────────────────────
restartSSH() {
    printf "%b\n" "${YELLOW}Restarting SSH daemon...${RC}"

    if "$ESCALATION_TOOL" systemctl restart sshd 2>/dev/null; then
        printf "%b\n" "${GREEN}✓ sshd restarted${RC}"
    elif "$ESCALATION_TOOL" systemctl restart ssh 2>/dev/null; then
        printf "%b\n" "${GREEN}✓ ssh restarted${RC}"
    else
        printf "%b\n" "${RED}✗ Failed to restart SSH daemon${RC}"
        printf "%b\n" "${YELLOW}Try manually: systemctl restart sshd${RC}"
        return 1
    fi
}

# ─── Print summary ────────────────────────────────────────────────────────
printSummary() {
    printf "%b\n" "${GREEN}========================================${RC}"
    printf "%b\n" "${GREEN}SSH Hardening Complete! 🔒${RC}"
    printf "%b\n" "${GREEN}========================================${RC}"

    printf "%b\n" "${CYAN}Settings applied:${RC}"
    printf "%b\n" "${CYAN}  • Port:                  ${SSH_PORT}${RC}"
    printf "%b\n" "${CYAN}  • Root login:            disabled${RC}"
    printf "%b\n" "${CYAN}  • Password auth:         disabled${RC}"
    printf "%b\n" "${CYAN}  • Pubkey auth:           enabled${RC}"
    printf "%b\n" "${CYAN}  • Max auth tries:        3${RC}"
    printf "%b\n" "${CYAN}  • Session timeout:       10 min${RC}"
    printf "%b\n" "${CYAN}  • X11 forwarding:        disabled${RC}"
    printf "%b\n" "${CYAN}  • TCP forwarding:        disabled${RC}"
    printf "%b\n" "${CYAN}  • Agent forwarding:      disabled${RC}"
    printf "%b\n" "${CYAN}  • Log level:             VERBOSE${RC}"

    if [ "$OPENSSH_MAJOR" -ge 10 ] 2>/dev/null; then
        printf "%b\n" "${CYAN}  • Post-quantum KEX:      enabled${RC}"
    elif [ "$OPENSSH_MAJOR" -ge 9 ] 2>/dev/null; then
        printf "%b\n" "${CYAN}  • Post-quantum KEX:      partial (sntrup761)${RC}"
    else
        printf "%b\n" "${CYAN}  • Post-quantum KEX:      classical only${RC}"
    fi

    printf "%b\n" "${CYAN}  • Config:                ${SSHD_HARDENING_CONF}${RC}"
    printf "%b\n" "${CYAN}  • Backups:               ${BACKUP_DIR}/${RC}"
    printf "%b\n" "${GREEN}========================================${RC}"
    printf "\n"
    printf "%b\n" "${YELLOW}⚠  CRITICAL: Test SSH access in a NEW terminal before${RC}"
    printf "%b\n" "${YELLOW}   closing this session!${RC}"
    printf "%b\n" "${YELLOW}   ssh -p ${SSH_PORT} <user>@<host>${RC}"
    printf "%b\n" "${GREEN}========================================${RC}"
}

# ─── Main execution ───────────────────────────────────────────────────────
checkEnv
checkEscalationTool
installSSH
detectOpenSSHVersion
selectKEX
askSSHPort
createBackup
ensureDropInDir
ensureHostKeys
createBanner
writeHardeningConfig
securePermissions
validateConfig
restartSSH
printSummary
