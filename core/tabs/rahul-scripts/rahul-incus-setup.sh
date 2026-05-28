#!/bin/sh -e

# Description: Install and validate Incus/LXC system containers for RahulOS Hermes fleet foundations.
# Works on: Arch, Fedora, openSUSE, Debian/Ubuntu when Incus is available in the configured repositories.

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
. "$SCRIPT_DIR/../common-script.sh"

checkEnv

TARGET_USER="${SUDO_USER:-${USER:-$(id -un)}}"
TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
if [ -z "$TARGET_HOME" ]; then
    TARGET_HOME="$HOME"
fi

HERMES_FLEET_DIR="${HERMES_FLEET_DIR:-$TARGET_HOME/.hermes-fleet}"
HERMES_POOL="${HERMES_POOL:-hermes-btrfs}"
HERMES_POOL_SIZE="${HERMES_POOL_SIZE:-40GiB}"
HERMES_PROFILE="${HERMES_PROFILE:-hermes-agent}"
HERMES_TEST_INSTANCE="${HERMES_TEST_INSTANCE:-hermes-test}"
DEFAULT_POOL="default"
DEFAULT_NETWORK="incusbr0"
SMOKE_CREATED=0

clear 2>/dev/null || true
printf "%b\n" "${CYAN}=================================================================${RC}"
printf "%b\n" "${YELLOW}        Rahul's Incus / LXC Setup for Hermes Fleet               ${RC}"
printf "%b\n" "${CYAN}=================================================================${RC}"
printf "%b\n" "${GREEN}  - Installs Incus and LXC dependencies where safely available${RC}"
printf "%b\n" "${GREEN}  - Fixes user/root subordinate UID/GID maps for unprivileged CTs${RC}"
printf "%b\n" "${GREEN}  - Initializes Incus once with a local bridge and dir pool${RC}"
printf "%b\n" "${GREEN}  - Creates optional ${HERMES_POOL} storage and ${HERMES_PROFILE} profile${RC}"
printf "%b\n" "${GREEN}  - Creates ${HERMES_FLEET_DIR} for future Hermes agents${RC}"
printf "%b\n" "${CYAN}=================================================================${RC}"
echo ""

cleanup_smoke() {
    if [ "$SMOKE_CREATED" = "1" ]; then
        incus_ctl stop "$HERMES_TEST_INSTANCE" --force >/dev/null 2>&1 || true
        incus_ctl delete "$HERMES_TEST_INSTANCE" >/dev/null 2>&1 || true
    fi
}

trap cleanup_smoke EXIT INT TERM

ask_yes_no_default() {
    prompt="$1"
    default="$2"

    if [ ! -t 0 ]; then
        case "$default" in
            y|Y|yes|YES) return 0 ;;
            *) return 1 ;;
        esac
    fi

    if [ "$default" = "y" ]; then
        printf "%b" "${CYAN}${prompt} [Y/n]: ${RC}"
    else
        printf "%b" "${CYAN}${prompt} [y/N]: ${RC}"
    fi
    read -r answer

    case "${answer:-$default}" in
        y|Y|yes|YES) return 0 ;;
        *) return 1 ;;
    esac
}

install_packages() {
    printf "\n%b\n" "${CYAN}━━━ Incus Packages ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RC}"

    case "$PACKAGER" in
        pacman)
            "$ESCALATION_TOOL" "$PACKAGER" -S --needed --noconfirm incus lxc lxcfs btrfs-progs squashfs-tools dnsmasq
            ;;
        dnf)
            "$ESCALATION_TOOL" "$PACKAGER" install -y incus lxc lxcfs btrfs-progs dnsmasq
            ;;
        zypper)
            "$ESCALATION_TOOL" "$PACKAGER" install -y incus lxc btrfsprogs dnsmasq
            ;;
        nala|apt-get|apt)
            "$ESCALATION_TOOL" apt-get update
            if apt-cache show incus >/dev/null 2>&1; then
                "$ESCALATION_TOOL" apt-get install -y incus
            else
                printf "%b\n" "${RED}[✗] Incus is not available in the configured apt repositories.${RC}"
                printf "%b\n" "${YELLOW}    Install Incus from your distro's supported repository, then rerun this script.${RC}"
                printf "%b\n" "${YELLOW}    This script avoids adding PPAs, snaps, or third-party repos automatically.${RC}"
                exit 1
            fi
            ;;
        apk)
            "$ESCALATION_TOOL" "$PACKAGER" add incus lxc lxcfs btrfs-progs squashfs-tools dnsmasq
            ;;
        xbps-install)
            "$ESCALATION_TOOL" "$PACKAGER" -Sy incus lxc lxcfs btrfs-progs squashfs-tools dnsmasq
            ;;
        *)
            printf "%b\n" "${RED}[✗] Unsupported package manager for automatic Incus install: $PACKAGER${RC}"
            printf "%b\n" "${YELLOW}    Install Incus manually, then rerun this script for idmap/profile/storage setup.${RC}"
            exit 1
            ;;
    esac

    if command_exists incus; then
        printf "%b\n" "${GREEN}[✓] incus is installed${RC}"
    fi
}

enable_incus() {
    printf "\n%b\n" "${CYAN}━━━ Incus Service ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RC}"

    if ! command_exists systemctl; then
        printf "%b\n" "${YELLOW}[~] systemctl not found. Start your Incus daemon manually, then rerun smoke.${RC}"
        return
    fi

    if systemctl list-unit-files incus.socket >/dev/null 2>&1; then
        "$ESCALATION_TOOL" systemctl enable --now incus.socket
        printf "%b\n" "${GREEN}[✓] incus.socket enabled and started${RC}"
    elif systemctl list-unit-files incus.service >/dev/null 2>&1; then
        "$ESCALATION_TOOL" systemctl enable --now incus.service
        printf "%b\n" "${GREEN}[✓] incus.service enabled and started${RC}"
    else
        printf "%b\n" "${YELLOW}[~] No Incus systemd unit found. Start Incus manually for this distro.${RC}"
    fi
}

ensure_group() {
    printf "\n%b\n" "${CYAN}━━━ User Access ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RC}"

    if getent group incus-admin >/dev/null 2>&1; then
        "$ESCALATION_TOOL" usermod -aG incus-admin "$TARGET_USER"
        printf "%b\n" "${GREEN}[✓] $TARGET_USER is added to incus-admin${RC}"
    else
        printf "%b\n" "${YELLOW}[~] incus-admin group not found. Package may use a distro-specific access model.${RC}"
    fi
}

append_line_if_missing() {
    file="$1"
    line="$2"

    if [ -f "$file" ] && grep -qxF "$line" "$file"; then
        return
    fi

    printf "%s\n" "$line" | "$ESCALATION_TOOL" tee -a "$file" >/dev/null
}

ensure_idmaps() {
    printf "\n%b\n" "${CYAN}━━━ Subordinate ID Maps ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RC}"

    append_line_if_missing /etc/subuid "$TARGET_USER:100000:65536"
    append_line_if_missing /etc/subgid "$TARGET_USER:100000:65536"
    append_line_if_missing /etc/subuid "root:1000000:1000000000"
    append_line_if_missing /etc/subgid "root:1000000:1000000000"

    printf "%b\n" "${GREEN}[✓] /etc/subuid and /etc/subgid contain user and root maps${RC}"

    if command_exists systemctl && systemctl is-active --quiet incus.service; then
        "$ESCALATION_TOOL" systemctl restart incus.service
        printf "%b\n" "${GREEN}[✓] incus.service restarted to reload idmaps${RC}"
    fi
}

incus_ctl() {
    if incus info >/dev/null 2>&1; then
        incus "$@"
    else
        "$ESCALATION_TOOL" incus "$@"
    fi
}

incus_initialized() {
    incus_ctl storage show "$DEFAULT_POOL" >/dev/null 2>&1 && \
        incus_ctl network show "$DEFAULT_NETWORK" >/dev/null 2>&1
}

initialize_incus() {
    printf "\n%b\n" "${CYAN}━━━ Incus Init ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RC}"

    if incus_initialized; then
        printf "%b\n" "${GREEN}[✓] Incus already initialized; leaving existing config unchanged${RC}"
        return
    fi

    printf "%b\n" "${YELLOW}[*] Initializing Incus with ${DEFAULT_NETWORK} and ${DEFAULT_POOL} dir pool...${RC}"
    incus_ctl admin init --preseed <<EOF
config: {}
networks:
  - name: ${DEFAULT_NETWORK}
    type: bridge
    config:
      ipv4.address: auto
      ipv6.address: none
storage_pools:
  - name: ${DEFAULT_POOL}
    driver: dir
profiles:
  - name: default
    devices:
      eth0:
        name: eth0
        network: ${DEFAULT_NETWORK}
        type: nic
      root:
        path: /
        pool: ${DEFAULT_POOL}
        type: disk
projects: []
cluster: null
EOF
    printf "%b\n" "${GREEN}[✓] Incus initialized${RC}"
}

free_space_allows_btrfs() {
    avail_kb="$(df -Pk "$TARGET_HOME" | awk 'NR == 2 {print $4}')"
    need_kb=$((45 * 1024 * 1024))
    [ "${avail_kb:-0}" -ge "$need_kb" ]
}

create_btrfs_pool() {
    printf "\n%b\n" "${CYAN}━━━ Hermes Storage Pool ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RC}"

    if incus_ctl storage show "$HERMES_POOL" >/dev/null 2>&1; then
        printf "%b\n" "${GREEN}[✓] Storage pool ${HERMES_POOL} already exists${RC}"
        return
    fi

    if ! command_exists btrfs; then
        printf "%b\n" "${YELLOW}[~] btrfs command not found; using default dir pool for Hermes profile.${RC}"
        return
    fi

    if ! free_space_allows_btrfs; then
        printf "%b\n" "${YELLOW}[~] Less than 45GiB free under $TARGET_HOME; skipping ${HERMES_POOL}.${RC}"
        return
    fi

    create_default="y"
    if [ "${RAHUL_INCUS_CREATE_BTRFS:-}" = "0" ]; then
        create_default="n"
    fi

    if ask_yes_no_default "Create ${HERMES_POOL} btrfs pool (${HERMES_POOL_SIZE}) for Hermes snapshots?" "$create_default"; then
        incus_ctl storage create "$HERMES_POOL" btrfs size="$HERMES_POOL_SIZE"
        printf "%b\n" "${GREEN}[✓] Created ${HERMES_POOL} (${HERMES_POOL_SIZE})${RC}"
    else
        printf "%b\n" "${YELLOW}[~] Skipped ${HERMES_POOL}; Hermes profile will use ${DEFAULT_POOL}.${RC}"
    fi
}

create_fleet_dirs() {
    printf "\n%b\n" "${CYAN}━━━ Hermes Fleet Folders ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RC}"

    mkdir -p \
        "$HERMES_FLEET_DIR/agents" \
        "$HERMES_FLEET_DIR/worktrees" \
        "$HERMES_FLEET_DIR/logs" \
        "$HERMES_FLEET_DIR/backups" \
        "$HERMES_FLEET_DIR/secrets"

    chmod 700 "$HERMES_FLEET_DIR" "$HERMES_FLEET_DIR/secrets"
    printf "%b\n" "${GREEN}[✓] Created ${HERMES_FLEET_DIR}{agents,worktrees,logs,backups,secrets}${RC}"
}

profile_device_exists() {
    profile="$1"
    device="$2"
    incus_ctl profile device get "$profile" "$device" type >/dev/null 2>&1
}

create_profile() {
    printf "\n%b\n" "${CYAN}━━━ Hermes Incus Profile ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RC}"

    if incus_ctl storage show "$HERMES_POOL" >/dev/null 2>&1; then
        root_pool="$HERMES_POOL"
    else
        root_pool="$DEFAULT_POOL"
    fi

    if ! incus_ctl profile show "$HERMES_PROFILE" >/dev/null 2>&1; then
        incus_ctl profile create "$HERMES_PROFILE"
        printf "%b\n" "${GREEN}[✓] Created profile ${HERMES_PROFILE}${RC}"
    else
        printf "%b\n" "${GREEN}[✓] Profile ${HERMES_PROFILE} already exists${RC}"
    fi

    if profile_device_exists "$HERMES_PROFILE" root; then
        incus_ctl profile device set "$HERMES_PROFILE" root path=/
        incus_ctl profile device set "$HERMES_PROFILE" root pool="$root_pool"
    else
        incus_ctl profile device add "$HERMES_PROFILE" root disk path=/ pool="$root_pool"
    fi

    if profile_device_exists "$HERMES_PROFILE" eth0; then
        incus_ctl profile device set "$HERMES_PROFILE" eth0 name=eth0
        incus_ctl profile device set "$HERMES_PROFILE" eth0 network="$DEFAULT_NETWORK"
    else
        incus_ctl profile device add "$HERMES_PROFILE" eth0 nic name=eth0 network="$DEFAULT_NETWORK"
    fi

    incus_ctl profile set "$HERMES_PROFILE" limits.cpu=2
    incus_ctl profile set "$HERMES_PROFILE" limits.memory=3GiB

    printf "%b\n" "${GREEN}[✓] ${HERMES_PROFILE} uses pool=${root_pool}, network=${DEFAULT_NETWORK}, cpu=2, memory=3GiB${RC}"
}

run_smoke_test() {
    printf "\n%b\n" "${CYAN}━━━ Optional Smoke Test ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RC}"

    smoke_default="n"
    if [ "${RAHUL_INCUS_RUN_SMOKE:-}" = "1" ]; then
        smoke_default="y"
    fi

    if ! ask_yes_no_default "Run disposable Debian smoke test now?" "$smoke_default"; then
        printf "%b\n" "${YELLOW}[~] Skipped smoke test.${RC}"
        return
    fi

    if incus_ctl info "$HERMES_TEST_INSTANCE" >/dev/null 2>&1; then
        printf "%b\n" "${RED}[✗] Instance ${HERMES_TEST_INSTANCE} already exists; not touching it.${RC}"
        return
    fi

    mkdir -p "$HERMES_FLEET_DIR/agents/$HERMES_TEST_INSTANCE"

    incus_ctl launch images:debian/13 "$HERMES_TEST_INSTANCE" --profile "$HERMES_PROFILE"
    SMOKE_CREATED=1
    incus_ctl config device add "$HERMES_TEST_INSTANCE" data disk \
        source="$HERMES_FLEET_DIR/agents/$HERMES_TEST_INSTANCE" path=/opt/data shift=true

    if [ -d "$TARGET_HOME/.work" ]; then
        incus_ctl config device add "$HERMES_TEST_INSTANCE" brain disk \
            source="$TARGET_HOME/.work" path="$TARGET_HOME/.work" readonly=true shift=true
    fi

    incus_ctl exec "$HERMES_TEST_INSTANCE" -- sh -lc 'apt update && touch /opt/data/incus-ok'

    if [ -f "$HERMES_FLEET_DIR/agents/$HERMES_TEST_INSTANCE/incus-ok" ]; then
        printf "%b\n" "${GREEN}[✓] Smoke test passed and /opt/data write reached host folder${RC}"
    else
        printf "%b\n" "${RED}[✗] Smoke test did not create incus-ok on the host${RC}"
        exit 1
    fi

    cleanup_smoke
    SMOKE_CREATED=0
}

print_next_steps() {
    printf "\n%b\n" "${CYAN}=================================================================${RC}"
    printf "%b\n" "${GREEN}Rahul's Incus / LXC foundation is ready.${RC}"
    printf "%b\n" "${CYAN}=================================================================${RC}"
    printf "%b\n" "${YELLOW}Next shell access:${RC}"
    printf "%b\n" "  newgrp incus-admin"
    printf "%b\n" "  incus info"
    printf "%b\n" ""
    printf "%b\n" "${YELLOW}Hermes fleet base:${RC}"
    printf "%b\n" "  ${HERMES_FLEET_DIR}"
    printf "%b\n" ""
    printf "%b\n" "${YELLOW}Future Hermes fleet scripts should use:${RC}"
    printf "%b\n" "  incus launch images:debian/13 <agent-name> --profile ${HERMES_PROFILE}"
    printf "%b\n" ""
    printf "%b\n" "${YELLOW}Reminder:${RC}"
    printf "%b\n" "  Do not mount the full home directory into agent containers."
    printf "%b\n" "  Use per-agent worktrees under ${HERMES_FLEET_DIR}/worktrees."
}

install_packages
enable_incus
ensure_group
ensure_idmaps
initialize_incus
create_btrfs_pool
create_fleet_dirs
create_profile
run_smoke_test
print_next_steps
