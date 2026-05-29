#!/bin/sh -e

# Description: Provision and configure isolated Hermes containers under Incus with safe mounts.
# Works on: Arch (and other supported Linux distributions with Incus installed)

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
. "$SCRIPT_DIR/../common-script.sh"

checkEnv

TARGET_USER="${SUDO_USER:-${USER:-$(id -un)}}"
TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
if [ -z "$TARGET_HOME" ]; then
    TARGET_HOME="$HOME"
fi

HERMES_FLEET_DIR="${HERMES_FLEET_DIR:-$TARGET_HOME/.hermes-fleet}"
HERMES_AGENT_SRC="${HERMES_AGENT_SRC:-$TARGET_HOME/.hermes/hermes-agent}"
HERMES_PROFILE="${HERMES_PROFILE:-hermes-agent}"

clear 2>/dev/null || true
printf "%b\n" "${CYAN}=================================================================${RC}"
printf "%b\n" "${YELLOW}      Rahul's isolated Hermes Fleet Container Provisioner        ${RC}"
printf "%b\n" "${CYAN}=================================================================${RC}"
printf "%b\n" "${GREEN}  - Configures secure per-agent directories under ~/.hermes-fleet${RC}"
printf "%b\n" "${GREEN}  - Localizes secret providers.env template without duplication ${RC}"
printf "%b\n" "${GREEN}  - Bind-mounts real ~/work (RW) into every container directly  ${RC}"
printf "%b\n" "${GREEN}  - Launches and configures unprivileged Incus CTs idempotently ${RC}"
printf "%b\n" "${GREEN}  - Hooks up read-only vault brain and writable host workspace   ${RC}"
printf "%b\n" "${GREEN}  - Installs hermes-agent virtualenv and initializes systemd    ${RC}"
printf "%b\n" "${CYAN}=================================================================${RC}"
echo ""

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

incus_ctl() {
    if incus info >/dev/null 2>&1; then
        incus "$@"
    else
        "$ESCALATION_TOOL" incus "$@"
    fi
}

ensure_fleet_dirs() {
    printf "\n%b\n" "${CYAN}━━━ Fleet Folders Setup ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RC}"

    mkdir -p "$HERMES_FLEET_DIR"
    chmod 700 "$HERMES_FLEET_DIR"

    mkdir -p "$HERMES_FLEET_DIR/secrets"
    chmod 700 "$HERMES_FLEET_DIR/secrets"

    mkdir -p "$HERMES_FLEET_DIR/logs" "$HERMES_FLEET_DIR/backups"
    chmod 700 "$HERMES_FLEET_DIR/logs" "$HERMES_FLEET_DIR/backups"

    # Ensure per-agent data directories exist
    # NOTE: No worktree clones — containers bind-mount the real ~/work directly.
    for container in hermes-haraka hermes-office hermes-client hermes-personal; do
        mkdir -p "$HERMES_FLEET_DIR/agents/$container/data"
        chmod 700 "$HERMES_FLEET_DIR/agents/$container"
    done

    printf "%b\n" "${GREEN}[✓] Fleet directories initialized and secured${RC}"
}

ensure_canonical_secrets() {
    printf "\n%b\n" "${CYAN}━━━ Secret providers.env Setup ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RC}"
    secret_file="$HERMES_FLEET_DIR/secrets/providers.env"

    if [ ! -f "$secret_file" ]; then
        cat > "$secret_file" <<EOF
# Canonical Hermes Fleet Secrets File
# Add your API keys here. They will be copied to each container's data/.env
#
# OPENROUTER_API_KEY=sk-or-v1-...
# OPENCODE_ZEN_API_KEY=sk-...
# NVIDIA_API_KEY=nvapi-...
# DEEPSEEK_API_KEY=sk-...
# GOOGLE_API_KEY=...
EOF
        chmod 600 "$secret_file"
        printf "%b\n" "${GREEN}[✓] Created empty secrets template at $secret_file${RC}"
        printf "%b\n" "${YELLOW}[!] Note: Fill this file with your real API keys later.${RC}"
    else
        printf "%b\n" "${GREEN}[✓] secrets file already exists at $secret_file${RC}"
    fi
}

seed_profile() {
    container="$1"
    profile_name="$2"
    source_dir="$TARGET_HOME/.hermes/profiles/$profile_name"
    target_dir="$HERMES_FLEET_DIR/agents/$container/data"

    mkdir -p "$target_dir"

    if [ -d "$source_dir" ]; then
        printf "%b\n" "${CYAN}━━━ Seeding $container data from host profile '$profile_name' ━━━${RC}"

        # Copy only safe non-live configurations
        for item in config.yaml MEMORY.md USER.md SOUL.md; do
            if [ -f "$source_dir/$item" ]; then
                cp "$source_dir/$item" "$target_dir/"
                printf "%b\n" "${GREEN}[✓] Seeded $item${RC}"
            fi
        done

        # Copy safe skills directory if present
        if [ -d "$source_dir/skills" ]; then
            cp -a "$source_dir/skills" "$target_dir/"
            printf "%b\n" "${GREEN}[✓] Seeded skills/${RC}"
        fi
    else
        printf "%b\n" "${YELLOW}[~] Host profile '$profile_name' not found; initializing clean config${RC}"
    fi

    # Ensure config.yaml is present on host
    config_file="$target_dir/config.yaml"
    if [ ! -f "$config_file" ]; then
        cat > "$config_file" <<EOF
model:
  provider: opencode-zen
  default: deepseek-v4-flash-free
  base_url: ''
credential_pool_strategies:
  opencode-zen: round_robin
EOF
        printf "%b\n" "${GREEN}[✓] Created config.yaml with OpenCode Zen default config${RC}"
    fi

    # Copy the providers.env to data/.env
    if [ -f "$HERMES_FLEET_DIR/secrets/providers.env" ]; then
        cp "$HERMES_FLEET_DIR/secrets/providers.env" "$target_dir/.env"
        chmod 600 "$target_dir/.env"
        printf "%b\n" "${GREEN}[✓] Copied secrets to data/.env${RC}"
    fi
}

# NOTE: clone_workspaces() removed.
# Containers now bind-mount the real ~/work host directory (RW) directly,
# so code changes inside the container are immediately visible on the host
# and to all other containers — no cloning, no sync delay.
# See ensure_disk_device "workspace" in setup_container() below.

ensure_disk_device() {
    container="$1"
    dev_name="$2"
    source_path="$3"
    target_path="$4"
    readonly_val="$5"

    if incus_ctl config device get "$container" "$dev_name" type >/dev/null 2>&1; then
        incus_ctl config device set "$container" "$dev_name" source="$source_path"
        incus_ctl config device set "$container" "$dev_name" path="$target_path"
        incus_ctl config device set "$container" "$dev_name" readonly="$readonly_val"
        incus_ctl config device set "$container" "$dev_name" shift=true
    else
        incus_ctl config device add "$container" "$dev_name" disk \
            source="$source_path" path="$target_path" readonly="$readonly_val" shift=true
    fi
}

ensure_proxy_device() {
    container="$1"
    dev_name="$2"
    listen_addr="$3"
    connect_addr="$4"

    if incus_ctl config device get "$container" "$dev_name" type >/dev/null 2>&1; then
        return 0
    fi

    incus_ctl config device add "$container" "$dev_name" proxy \
        listen="$listen_addr" connect="$connect_addr"
}

sync_opencode_zen_pool() {
    container="$1"
    env_file="$HERMES_FLEET_DIR/secrets/providers.env"

    if [ ! -f "$env_file" ]; then
        printf "%b\n" "${YELLOW}[~] No secrets file found at $env_file; skipping key pool sync${RC}"
        return 0
    fi

    printf "%b\n" "${YELLOW}[*] Syncing OpenCode Zen keys for $container...${RC}"

    # Capture outputs inside the container to a log file, redirecting stderr and stdout
    incus_ctl exec "$container" -- sh -c '
    if [ ! -f /opt/data/.env ]; then
        exit 2
    fi

    . /opt/data/.env

    existing_auth=""
    if [ -x /usr/local/bin/hermes ]; then
        existing_auth=$(su - rahul -c "cd /home/rahul && HERMES_HOME=/opt/data /usr/local/bin/hermes auth list opencode-zen" 2>/dev/null || true)
    fi

    # Check for duplicate labels strictly from list output column 2
    duplicates=$(echo "$existing_auth" | awk '\''{print $2}'\'' | sort | uniq -d | grep -E "^zen-pool-" || true)
    if [ -n "$duplicates" ]; then
        echo "DUPLICATE_LABELS_DETECTED"
    fi

    keys_found=0
    keys_synced=0
    label_support_failed=0

    for i in 1 2 3 4 5 6 7 8 9 10; do
        if [ "$i" = "1" ]; then
            var_name="OPENCODE_ZEN_API_KEY"
        else
            var_name="OPENCODE_ZEN_API_KEY_$i"
        fi

        eval key=\${$var_name:-}

        if [ -n "$key" ]; then
            keys_found=$((keys_found + 1))
            label="zen-pool-$i"

            # Check if label already exists using strict column match
            if echo "$existing_auth" | awk '\''{print $2}'\'' | grep -qx "$label"; then
                keys_synced=$((keys_synced + 1))
                continue
            fi

            rm -f /tmp/hermes-auth-err.log

            # 1. Try with label and correct argument order (provider opencode-zen at the end)
            su - rahul -c "cd /home/rahul && HERMES_HOME=/opt/data /usr/local/bin/hermes auth add --type api-key --api-key '$key' --label '$label' opencode-zen" >/tmp/hermes-auth-err.log 2>&1
            status=$?

            if [ "$status" = "0" ]; then
                keys_synced=$((keys_synced + 1))
            else
                # Check for label support error
                if grep -qi "unrecognized arguments: --label" /tmp/hermes-auth-err.log; then
                    label_support_failed=1
                    # 2. Try fallback without label
                    su - rahul -c "cd /home/rahul && HERMES_HOME=/opt/data /usr/local/bin/hermes auth add --type api-key --api-key '$key' opencode-zen" >/tmp/hermes-auth-err.log 2>&1
                    status=$?
                    if [ "$status" = "0" ]; then
                        keys_synced=$((keys_synced + 1))
                    fi
                fi

                if [ "$status" != "0" ]; then
                    echo "Command shape: hermes auth add --type api-key --api-key [REDACTED] --label $label opencode-zen"
                    echo "Error output:"
                    # Mask key and a portion of it to keep secrets safe
                    masked_key=$(echo "$key" | cut -c 1-8)
                    sed "s/$key/[REDACTED]/g; s/$masked_key/[REDACTED]/g" /tmp/hermes-auth-err.log
                fi
            fi
        fi
    done

    # Clean up temp file inside container
    rm -f /tmp/hermes-auth-err.log

    if [ "$label_support_failed" = "1" ]; then
        echo "LABEL_SUPPORT_FAILED"
    elif [ "$keys_found" -eq 0 ]; then
        echo "NO_KEYS"
    elif [ "$keys_synced" -eq "$keys_found" ]; then
        echo "SUCCESS"
    else
        echo "PARTIAL_SUCCESS"
    fi
    ' > /tmp/hermes-sync-status.log 2>&1 || true

    # Display duplicate warnings to host stdout if found
    if grep -q "DUPLICATE_LABELS_DETECTED" /tmp/hermes-sync-status.log; then
        printf "%b\n" "${YELLOW}[~] Existing duplicate labels detected; not adding more. Clean manually if Rahul approves.${RC}"
    fi

    # Display sanitized logs to host stdout
    grep -v -E "LABEL_SUPPORT_FAILED|NO_KEYS|SUCCESS|PARTIAL_SUCCESS|DUPLICATE_LABELS_DETECTED" /tmp/hermes-sync-status.log || true
    sync_status=$(tail -n 1 /tmp/hermes-sync-status.log)
    rm -f /tmp/hermes-sync-status.log

    if [ "$sync_status" = "SUCCESS" ]; then
        printf "%b\n" "${GREEN}[✓] Synced OpenCode Zen key pool for $container${RC}"
    elif [ "$sync_status" = "LABEL_SUPPORT_FAILED" ]; then
        printf "%b\n" "${YELLOW}[~] Hermes auth add has no label support; skipping duplicate-safe import.${RC}"
        printf "%b\n" "${YELLOW}[~] Synced providers.env to /opt/data/.env; manual pool import needed.${RC}"
    elif [ "$sync_status" = "NO_KEYS" ]; then
        printf "%b\n" "${YELLOW}[~] No OpenCode Zen keys found in providers.env${RC}"
    else
        printf "%b\n" "${YELLOW}[~] Synced providers.env to /opt/data/.env; manual pool import needed.${RC}"
    fi

    return 0
}

setup_container() {
    container="$1"
    profile_name="$2"
    scope_dir="$3"
    haraka_write="$4"

    printf "\n%b\n" "${CYAN}━━━ Setting up Container: $container ━━━━━━━━━━━━━━━━━━━━━━━━${RC}"

    if ! incus_ctl info "$container" >/dev/null 2>&1; then
        printf "%b\n" "${YELLOW}[*] Launching new $container container...${RC}"
        incus_ctl launch images:debian/13 "$container" --profile "$HERMES_PROFILE"
        incus_ctl config set "$container" security.nesting true
        printf "%b\n" "${GREEN}[✓] Container launched${RC}"
    else
        printf "%b\n" "${GREEN}[✓] Container '$container' already exists (updating config)${RC}"
    fi

    # Seed profile data
    seed_profile "$container" "$profile_name"

    # ── Disk mounts ──────────────────────────────────────────────────────────
    # /opt/data        → per-agent Hermes config/data (RW, isolated per agent)
    # /opt/hermes-agent → hermes-agent source binary   (RO, shared read)
    # /home/rahul/work → REAL host ~/work workspace    (RW, bind-mount — code
    #                    changes are IMMEDIATELY on the host disk, no clone!)
    # /home/rahul/.work → vault brain                  (RO by default; Haraka
    #                    may get RW if RAHUL_HARAKA_BRAIN_WRITE=1)
    # ─────────────────────────────────────────────────────────────────────────
    ensure_disk_device "$container" data        "$HERMES_FLEET_DIR/agents/$container/data" /opt/data          false
    ensure_disk_device "$container" hermes-agent "$HERMES_AGENT_SRC"                        /opt/hermes-agent  true

    # FIX: mount the real host ~/work directory, NOT a worktree clone.
    # This ensures code edits inside the container go directly to the host
    # filesystem and are visible to all other containers and the host instantly.
    ensure_disk_device "$container" workspace   "$TARGET_HOME/work"                         /home/rahul/work   false

    # Brain mount: full vault RO for all agents.
    # Buddy agents can READ the full vault (cross-scope context is useful).
    # The RO flag enforces the write gate — vault writes must go through Git.
    brain_readonly=true
    if [ "$container" = "hermes-haraka" ]; then
        brain_readonly="$haraka_write"
        ensure_proxy_device "$container" dashboard "tcp:127.0.0.1:9119" "tcp:127.0.0.1:9119"
    fi
    ensure_disk_device "$container" brain "$TARGET_HOME/.work" /home/rahul/.work "$brain_readonly"

    printf "%b\n" "${GREEN}[✓] Disk and proxy devices mapped with shift=true${RC}"
    printf "%b\n" "  workspace → bind-mount of $TARGET_HOME/work (RW, real host dir)"
    printf "%b\n" "  brain     → bind-mount of $TARGET_HOME/.work (readonly=$brain_readonly)"

    # Boot container if stopped
    if ! incus_ctl info "$container" 2>/dev/null | grep -q "Status: RUNNING"; then
        incus_ctl start "$container"
        sleep 2
    fi

    # Stop gateway service and kill any running hermes processes to avoid directory locks
    printf "%b\n" "${YELLOW}[*] Stopping gateway and cleaning old processes inside container...${RC}"
    incus_ctl exec "$container" -- systemctl stop hermes-gateway.service 2>/dev/null || true
    incus_ctl exec "$container" -- pkill -9 -f "tui_gateway.entry" || true
    incus_ctl exec "$container" -- pkill -9 -f "ui-tui" || true
    incus_ctl exec "$container" -- pkill -9 -f "hermes" || true

    # Provision container
    printf "%b\n" "${YELLOW}[*] Provisioning container environment...${RC}"
    incus_ctl exec "$container" -- apt-get update -qq
    incus_ctl exec "$container" -- apt-get install -y -qq python3 python3-pip python3-venv git curl build-essential nodejs npm sudo

    # Configure rahul user
    incus_ctl exec "$container" -- sh -c '
    if ! getent group rahul >/dev/null 2>&1; then
        groupadd -g 1000 rahul
    fi
    if ! getent passwd rahul >/dev/null 2>&1; then
        useradd -u 1000 -g 1000 -m -s /bin/bash rahul
    fi
    echo "rahul ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/rahul
    chmod 440 /etc/sudoers.d/rahul
    '

    # Ensure home directory exists and is owned by rahul
    incus_ctl exec "$container" -- sh -c '
    mkdir -p /home/rahul
    chown rahul:rahul /home/rahul
    chmod 755 /home/rahul
    '

    # Make mounts owned by rahul safely
    incus_ctl exec "$container" -- chown -R rahul:rahul /opt/data
    # NOTE: We do NOT recursively chown /home/rahul/work — it is a bind-mount
    # of the real host ~/work directory. A recursive chown here would change
    # ownership on the host disk, which is destructive. The container user
    # (rahul uid=1000) already matches the host user, so access works via the
    # shift=true UID mapping set on the disk device.
    printf "%b\n" "${YELLOW}[~] Skipping chown on /home/rahul/work (real host bind-mount — shift=true handles UID mapping)${RC}"

    # Sync gitconfig if exists
    if [ -f "$TARGET_HOME/.gitconfig" ]; then
        incus_ctl file push "$TARGET_HOME/.gitconfig" "$container/home/rahul/.gitconfig"
        incus_ctl exec "$container" -- chown rahul:rahul /home/rahul/.gitconfig
    fi

    # Clean up broken virtualenv if pip is missing
    incus_ctl exec "$container" -- sh -c '
    if [ -d /home/rahul/.hermes-venv ] && [ ! -x /home/rahul/.hermes-venv/bin/pip ]; then
        rm -rf /home/rahul/.hermes-venv
    fi
    '

    # Copy read-only source into a persistent writable directory to allow editable install
    incus_ctl exec "$container" -- sh -c '
    rm -rf /home/rahul/hermes-agent-src
    mkdir -p /home/rahul/hermes-agent-src
    cp -a /opt/hermes-agent/. /home/rahul/hermes-agent-src/
    chown -R rahul:rahul /home/rahul/hermes-agent-src
    '

    # Apply local patch to web_server.py to resolve the dashboard embedded TUI cwd issue
    incus_ctl exec "$container" -- python3 -c '
from pathlib import Path
p = Path("/home/rahul/hermes-agent-src/hermes_cli/web_server.py")
if p.exists():
    content = p.read_text()
    old = "argv, cwd = _make_tui_argv(PROJECT_ROOT / \"ui-tui\", tui_dev=False)"
    new = "argv, _ = _make_tui_argv(PROJECT_ROOT / \"ui-tui\", tui_dev=False); cwd = Path(os.environ.get(\"HERMES_DASHBOARD_TUI_CWD\", str(Path.home())))"
    if old in content:
        p.write_text(content.replace(old, new))
        print("[✓] Patched web_server.py in container")
    else:
        print("[~] Target pattern not found in web_server.py")
'

    # Install hermes inside container virtualenv
    printf "%b\n" "${YELLOW}[*] Installing hermes-agent to container virtualenv...${RC}"
    incus_ctl exec "$container" -- su - rahul -c '
    if [ ! -d "/home/rahul/.hermes-venv" ]; then
        python3 -m venv /home/rahul/.hermes-venv
    fi
    /home/rahul/.hermes-venv/bin/pip install -q --upgrade pip
    '

    if [ "$container" = "hermes-haraka" ]; then
        printf "%b\n" "${YELLOW}[*] Installing hermes-agent with dashboard dependencies into hermes-haraka...${RC}"
        incus_ctl exec "$container" -- su - rahul -c '
        /home/rahul/.hermes-venv/bin/pip install -q -e /home/rahul/hermes-agent-src
        /home/rahul/.hermes-venv/bin/pip install -q fastapi "uvicorn[standard]" websockets PyYAML ptyprocess
        '
    else
        incus_ctl exec "$container" -- su - rahul -c '
        /home/rahul/.hermes-venv/bin/pip install -q -e /home/rahul/hermes-agent-src
        /home/rahul/.hermes-venv/bin/pip install -q PyYAML
        '
    fi

    # Update config.yaml using container Python environment
    printf "%b\n" "${YELLOW}[*] Updating config.yaml with OpenCode Zen default config inside container...${RC}"
    incus_ctl exec "$container" -- sh -c '
    /home/rahul/.hermes-venv/bin/python - << "PY"
from pathlib import Path
import yaml

path = Path("/opt/data/config.yaml")
data = {}
if path.exists() and path.read_text().strip():
    data = yaml.safe_load(path.read_text()) or {}

data.setdefault("model", {})
data["model"]["provider"] = "opencode-zen"
data["model"]["default"] = "deepseek-v4-flash-free"
data["model"]["base_url"] = ""

data.setdefault("credential_pool_strategies", {})
data["credential_pool_strategies"]["opencode-zen"] = "round_robin"

tmp = path.with_suffix(".yaml.tmp")
tmp.write_text(yaml.safe_dump(data, sort_keys=False))
yaml.safe_load(tmp.read_text())
tmp.replace(path)
PY
'
    incus_ctl exec "$container" -- chown rahul:rahul /opt/data/config.yaml

    # Validate written config
    config_valid=true
    if ! incus_ctl exec "$container" -- /home/rahul/.hermes-venv/bin/python -c "import yaml; yaml.safe_load(open('/opt/data/config.yaml')); print('yaml-ok')" >/dev/null 2>&1; then
        printf "%b\n" "${YELLOW}[~] config.yaml validation failed for $container!${RC}"
        config_valid=false
    fi

    # Create hermes command wrapper
    incus_ctl exec "$container" -- sh -c 'cat > /usr/local/bin/hermes <<EOF
#!/usr/bin/env bash
unset PYTHONPATH
unset PYTHONHOME
export HERMES_HOME=/opt/data
exec "/home/rahul/.hermes-venv/bin/hermes" "\$@"
EOF
chmod +x /usr/local/bin/hermes'

    # Sync OpenCode Zen keys
    sync_opencode_zen_pool "$container"

    # Set up systemd service
    printf "%b\n" "${YELLOW}[*] Configuring hermes-gateway systemd service...${RC}"
    incus_ctl exec "$container" -- sh -c 'cat > /etc/systemd/system/hermes-gateway.service <<EOF
[Unit]
Description=Hermes Agent Gateway
After=network.target

[Service]
Type=simple
User=rahul
WorkingDirectory=/home/rahul
Environment=HERMES_HOME=/opt/data
ExecStart=/usr/local/bin/hermes gateway run
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload'

    if [ "$config_valid" = "true" ]; then
        if [ "$container" = "hermes-haraka" ]; then
            # Clean old dashboard/TUI child processes inside hermes-haraka before startup
            printf "%b\n" "${YELLOW}[*] Cleaning old dashboard/TUI child processes inside hermes-haraka...${RC}"
            incus_ctl exec "$container" -- pkill -9 -f "tui_gateway.entry" || true
            incus_ctl exec "$container" -- pkill -9 -f "ui-tui" || true
            incus_ctl exec "$container" -- pkill -9 -f "hermes dashboard" || true

            incus_ctl exec "$container" -- systemctl enable --now hermes-gateway.service
            printf "%b\n" "${GREEN}[✓] Started hermes-gateway.service on hermes-haraka${RC}"

            # Start dashboard in background
            printf "%b\n" "${YELLOW}[*] Starting hermes dashboard inside hermes-haraka...${RC}"
            incus_ctl exec "$container" -- su - rahul -c "cd /home/rahul && HERMES_HOME=/opt/data HERMES_DASHBOARD_TUI=1 HERMES_DASHBOARD_TUI_CWD=/home/rahul HERMES_TUI_INLINE=0 nohup hermes dashboard --host 127.0.0.1 --port 9119 --no-open > /opt/data/dashboard.log 2>&1 &"
            sleep 2
        else
            incus_ctl exec "$container" -- systemctl disable --now hermes-gateway.service 2>/dev/null || true
            printf "%b\n" "${YELLOW}[~] Disabled hermes-gateway.service on $container (CLI-ready mode)${RC}"
        fi
    else
        printf "%b\n" "${YELLOW}[~] Warning: Skipping starting/enabling hermes-gateway on $container due to invalid config.${RC}"
    fi

    printf "%b\n" "${GREEN}[✓] Container setup complete${RC}"
}

# Main execution logic
if [ ! -d "$HERMES_AGENT_SRC" ]; then
    printf "%b\n" "${RED}[✗] Missing hermes-agent source repository at $HERMES_AGENT_SRC${RC}"
    exit 1
fi

# 1. Ask for Haraka brain write permission
haraka_brain_readonly="true"
if [ "${RAHUL_HARAKA_BRAIN_WRITE:-}" = "1" ]; then
    haraka_brain_readonly="false"
elif [ "${RAHUL_HARAKA_BRAIN_WRITE:-}" = "0" ]; then
    haraka_brain_readonly="true"
else
    if ask_yes_no_default "Enable WRITE access to main brain (~/.work) for hermes-haraka?" "n"; then
        haraka_brain_readonly="false"
    else
        haraka_brain_readonly="true"
    fi
fi

# 2. Build foundation
ensure_fleet_dirs
ensure_canonical_secrets

# 3. Setup four container fleet
# scope_dir arg is now unused (no more worktree cloning) but kept for
# future filtering use; pass empty string to all containers.
setup_container hermes-haraka  haraka         "" "$haraka_brain_readonly"
setup_container hermes-office  office-buddy   "" "true"
setup_container hermes-client  client-buddy   "" "true"
setup_container hermes-personal personal-buddy "" "true"

printf "\n%b\n" "${CYAN}=================================================================${RC}"
printf "%b\n" "${GREEN}Rahul's Hermes Fleet Provisioning has completed successfully.${RC}"
printf "%b\n" "${CYAN}=================================================================${RC}"
printf "%b\n" "${YELLOW}Verification Commands:${RC}"
printf "%b\n" "  incus exec hermes-haraka -- su - rahul -c \"cd /home/rahul && HERMES_HOME=/opt/data hermes --version\""
printf "%b\n" "  incus exec hermes-office -- su - rahul -c \"cd /home/rahul && HERMES_HOME=/opt/data hermes --version\""
printf "%b\n" "  incus exec hermes-client -- su - rahul -c \"cd /home/rahul && HERMES_HOME=/opt/data hermes --version\""
printf "%b\n" "  incus exec hermes-personal -- su - rahul -c \"cd /home/rahul && HERMES_HOME=/opt/data hermes --version\""
printf "%b\n" ""
printf "%b\n" "  incus exec hermes-haraka -- /home/rahul/.hermes-venv/bin/python -c \"import yaml; d=yaml.safe_load(open('/opt/data/config.yaml')); print(d['model']['provider'], d['model']['default'], d['credential_pool_strategies']['opencode-zen'])\""
printf "%b\n" ""
printf "%b\n" "  incus exec hermes-haraka -- su - rahul -c \"cd /home/rahul && HERMES_HOME=/opt/data hermes auth list opencode-zen\""
printf "%b\n" ""
printf "%b\n" "  incus exec hermes-haraka -- su - rahul -c \"cd /home/rahul && HERMES_HOME=/opt/data hermes -m deepseek-v4-flash-free --provider opencode-zen -z 'Reply with exactly: haraka ok'\""
printf "%b\n" "  incus exec hermes-office -- su - rahul -c \"cd /home/rahul && HERMES_HOME=/opt/data hermes -m deepseek-v4-flash-free --provider opencode-zen -z 'Reply with exactly: office ok'\""
printf "%b\n" "  incus exec hermes-client -- su - rahul -c \"cd /home/rahul && HERMES_HOME=/opt/data hermes -m deepseek-v4-flash-free --provider opencode-zen -z 'Reply with exactly: client ok'\""
printf "%b\n" "  incus exec hermes-personal -- su - rahul -c \"cd /home/rahul && HERMES_HOME=/opt/data hermes -m deepseek-v4-flash-free --provider opencode-zen -z 'Reply with exactly: personal ok'\""
printf "%b\n" ""
printf "%b\n" "  incus exec hermes-haraka -- systemctl is-active hermes-gateway"
printf "%b\n" "  incus exec hermes-office -- systemctl is-enabled hermes-gateway"
printf "%b\n" "  incus exec hermes-client -- systemctl is-enabled hermes-gateway"
printf "%b\n" "  incus exec hermes-personal -- systemctl is-enabled hermes-gateway"
printf "%b\n" ""
printf "%b\n" "${YELLOW}Dashboard URL:${RC}"
printf "%b\n" "  http://127.0.0.1:9119/chat"
printf "%b\n" ""
printf "%b\n" "${YELLOW}If chat shows 'gateway exited':${RC}"
printf "%b\n" "  1. Run dashboard clean restart:"
printf "%b\n" "     incus exec hermes-haraka -- pkill -9 -f tui_gateway.entry || true"
printf "%b\n" "     incus exec hermes-haraka -- pkill -9 -f ui-tui || true"
printf "%b\n" "     incus exec hermes-haraka -- pkill -9 -f 'hermes dashboard' || true"
printf "%b\n" "     incus exec hermes-haraka -- su - rahul -c \"cd /home/rahul && HERMES_HOME=/opt/data HERMES_DASHBOARD_TUI=1 HERMES_DASHBOARD_TUI_CWD=/home/rahul HERMES_TUI_INLINE=0 nohup hermes dashboard --host 127.0.0.1 --port 9119 --no-open > /opt/data/dashboard.log 2>&1 &\""
printf "%b\n" "  2. Browser hard refresh with Ctrl+Shift+R."
printf "%b\n" "  3. If still stale, open in incognito/private window."
printf "%b\n" "================================================================="
