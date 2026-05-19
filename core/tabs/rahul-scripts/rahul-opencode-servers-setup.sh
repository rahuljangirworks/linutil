#!/bin/sh -e

# Description: Install and manage five local OpenCode servers for RahulOS
# Works on: Arch, Debian, Fedora, openSUSE, Void, Alpine, Solus

. ../common-script.sh

checkEnv

NPM_GLOBAL="$HOME/.npm-global"
MANAGER="$HOME/.local/bin/opencode-servers"
RAHULOS_VAULT="${RAHULOS_VAULT:-$HOME/.work}"
RAHULOS_WORKSPACE="${RAHULOS_WORKSPACE:-$HOME/work}"

clear 2>/dev/null || true
printf "%b\n" "${CYAN}=================================================================${RC}"
printf "%b\n" "${YELLOW}        Rahul's OpenCode Servers 1-5 Setup                       ${RC}"
printf "%b\n" "${CYAN}=================================================================${RC}"
printf "%b\n" "${GREEN}  - Creates five local OpenCode servers on ports 4096-4100${RC}"
printf "%b\n" "${GREEN}  - Gives all servers access to $RAHULOS_VAULT and $RAHULOS_WORKSPACE${RC}"
printf "%b\n" "${GREEN}  - Keeps each server's OpenCode auth/data isolated${RC}"
printf "%b\n" "${GREEN}  - Installs manager command: $MANAGER${RC}"
printf "%b\n" "${CYAN}=================================================================${RC}"
echo ""

install_pkg_if_missing() {
    cmd="$1"
    pkg="$2"

    if command_exists "$cmd"; then
        printf "%b\n" "${GREEN}[✓] $cmd already installed${RC}"
        return
    fi

    printf "%b\n" "${YELLOW}[*] Installing $pkg...${RC}"
    case "$PACKAGER" in
        pacman)
            "$ESCALATION_TOOL" "$PACKAGER" -S --needed --noconfirm "$pkg"
            ;;
        apk)
            "$ESCALATION_TOOL" "$PACKAGER" add "$pkg"
            ;;
        xbps-install)
            "$ESCALATION_TOOL" "$PACKAGER" -Sy "$pkg"
            ;;
        nala|apt-get|apt)
            "$ESCALATION_TOOL" apt-get update
            "$ESCALATION_TOOL" apt-get install -y "$pkg"
            ;;
        dnf|zypper|eopkg)
            "$ESCALATION_TOOL" "$PACKAGER" install -y "$pkg"
            ;;
        *)
            printf "%b\n" "${RED}[✗] Cannot install $pkg automatically.${RC}"
            exit 1
            ;;
    esac
}

setup_npm_global() {
    if [ "$(id -u)" = "0" ]; then
        return
    fi

    mkdir -p "$NPM_GLOBAL/bin"
    npm config set prefix "$NPM_GLOBAL" >/dev/null 2>&1 || true

    case ":$PATH:" in
        *:"$NPM_GLOBAL/bin":*) ;;
        *) export PATH="$NPM_GLOBAL/bin:$PATH" ;;
    esac
}

install_dependencies() {
    install_pkg_if_missing bash bash
    install_pkg_if_missing curl curl
    install_pkg_if_missing node nodejs
    install_pkg_if_missing npm npm
    install_pkg_if_missing systemctl systemd

    if ! command_exists openssl; then
        case "$PACKAGER" in
            pacman|apk|xbps-install|nala|apt-get|apt|dnf|zypper|eopkg)
                install_pkg_if_missing openssl openssl
                ;;
            *)
                printf "%b\n" "${YELLOW}[~] openssl missing; manager will fall back to /dev/urandom.${RC}"
                ;;
        esac
    else
        printf "%b\n" "${GREEN}[✓] openssl already installed${RC}"
    fi
}

install_opencode_cli() {
    printf "\n%b\n" "${CYAN}━━━ OpenCode CLI ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RC}"

    if command_exists opencode; then
        printf "%b\n" "${GREEN}[✓] opencode CLI already installed — $(opencode --version 2>/dev/null || echo installed)${RC}"
        return
    fi

    if [ "$PACKAGER" = "pacman" ]; then
        printf "%b\n" "${YELLOW}[*] Installing OpenCode CLI from Arch package repo...${RC}"
        "$ESCALATION_TOOL" pacman -S --needed --noconfirm opencode || {
            printf "%b\n" "${YELLOW}[~] pacman install failed; falling back to npm.${RC}"
            setup_npm_global
            npm install -g opencode-ai@latest
        }
    else
        printf "%b\n" "${YELLOW}[*] Installing OpenCode CLI with npm...${RC}"
        setup_npm_global
        npm install -g opencode-ai@latest
    fi
}

write_manager() {
    printf "\n%b\n" "${CYAN}━━━ Manager Command ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RC}"
    mkdir -p "$HOME/.local/bin"

    cat > "$MANAGER" <<'MANAGER_EOF'
#!/usr/bin/env bash
set -euo pipefail

BASE_CONFIG="${OPENCODE_SERVERS_CONFIG_BASE:-$HOME/.config/opencode-servers}"
BASE_DATA="${OPENCODE_SERVERS_DATA_BASE:-$HOME/.local/share/opencode-servers}"
BASE_STATE="${OPENCODE_SERVERS_STATE_BASE:-$HOME/.local/state/opencode-servers}"
SYSTEMD_USER_DIR="$HOME/.config/systemd/user"
SERVICE_FILE="$SYSTEMD_USER_DIR/opencode-server@.service"
SHARED_CONFIG="$BASE_CONFIG/shared/opencode.json"
# Detect opencode binary: prefer command in PATH, fall back to npm-global, opencode dir, then default
if command -v opencode >/dev/null 2>&1; then
  OPENCODE_BIN="$(command -v opencode)"
else
  OPENCODE_BIN="${OPENCODE_BIN:-$HOME/.npm-global/bin/opencode}"
fi
RAHULOS_VAULT="${RAHULOS_VAULT:-$HOME/.work}"
RAHULOS_WORKSPACE="${RAHULOS_WORKSPACE:-$HOME/work}"
PORT_BASE=4095
SERVER_COUNT=5

usage() {
  cat <<USAGE
Usage: opencode-servers <command> [server-number]

Commands:
  install             Create config, env files, and systemd user template
  start               Start all servers 1-5
  stop                Stop all servers 1-5
  restart             Restart all servers 1-5
  status              Show status for all servers 1-5
  logs <N>            Follow logs for server N
  login <N> [args...] Run provider login in server N's isolated profile
  attach <N> [args...] Attach to server N with /home/rahul/.work as dir
  serve <N>           Internal command used by systemd
  print-desktop       Print OpenCode Desktop server entries
  passwords           Print server usernames and passwords
USAGE
}

require_server_number() {
  local number="${1:-}"
  case "$number" in
    1|2|3|4|5) return 0 ;;
    *) echo "Expected server number 1-5" >&2; exit 2 ;;
  esac
}

port_for() {
  local number="$1"
  echo $((PORT_BASE + number))
}

server_dir() {
  local number="$1"
  echo "$BASE_CONFIG/server-$number"
}

env_file() {
  local number="$1"
  echo "$(server_dir "$number")/server.env"
}

generate_password() {
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -base64 24 | tr -d '\n'
  else
    tr -dc 'A-Za-z0-9_@%+=:.,-' < /dev/urandom | head -c 32
  fi
}

write_shared_config() {
  mkdir -p "$(dirname "$SHARED_CONFIG")"
  cat > "$SHARED_CONFIG" <<JSON
{
  "\$schema": "https://opencode.ai/config.json",
  "autoupdate": "notify",
  "watcher": {
    "ignore": [
      "**/node_modules/**",
      "**/.git/**",
      "**/dist/**",
      "**/build/**",
      "**/.next/**",
      "**/coverage/**",
      "**/.cache/**",
      "**/target/**",
      "**/.venv/**",
      "**/__pycache__/**"
    ]
  },
  "mcp": {
    "filesystem-rahulos": {
      "type": "local",
      "command": [
        "npx",
        "-y",
        "@modelcontextprotocol/server-filesystem",
        "$RAHULOS_VAULT",
        "$RAHULOS_WORKSPACE"
      ],
      "enabled": true
    },
    "fetch": { "enabled": false },
    "git": { "enabled": false },
    "context7": { "enabled": false },
    "desktop-commander-local": { "enabled": false },
    "playwright": { "enabled": false },
    "open-websearch": { "enabled": false },
    "sqlite": { "enabled": false },
    "memory": { "enabled": false },
    "carbone-mcp": { "enabled": false },
    "github": { "enabled": false },
    "oci-memory-cloudflare": { "enabled": false }
  }
}
JSON
}

write_server_envs() {
  local number port dir file password
  for number in $(seq 1 "$SERVER_COUNT"); do
    port="$(port_for "$number")"
    dir="$(server_dir "$number")"
    file="$(env_file "$number")"
    mkdir -p "$dir" "$BASE_DATA/server-$number/data" "$BASE_STATE/server-$number/state"
    if [ -f "$file" ]; then
      chmod 600 "$file"
      continue
    fi
    password="$(generate_password)"
    cat > "$file" <<ENV
OPENCODE_SERVER_USERNAME=opencode
OPENCODE_SERVER_PASSWORD=$password
OPENCODE_SERVER_PORT=$port
OPENCODE_SERVER_NUMBER=$number
ENV
    chmod 600 "$file"
  done
}

write_service_file() {
  mkdir -p "$SYSTEMD_USER_DIR"
  cat > "$SERVICE_FILE" <<SERVICE
[Unit]
Description=OpenCode Server %i
After=network-online.target

[Service]
Type=simple
EnvironmentFile=%h/.config/opencode-servers/server-%i/server.env
ExecStart=%h/.local/bin/opencode-servers serve %i
Restart=on-failure
RestartSec=3
WorkingDirectory=%h/.work

[Install]
WantedBy=default.target
SERVICE
}

install_all() {
  if [ ! -x "$OPENCODE_BIN" ]; then
    echo "OpenCode binary not found or not executable: $OPENCODE_BIN" >&2
    exit 1
  fi
  mkdir -p "$BASE_CONFIG" "$BASE_DATA" "$BASE_STATE" "$RAHULOS_VAULT" "$RAHULOS_WORKSPACE"
  write_shared_config
  write_server_envs
  write_service_file
  systemctl --user daemon-reload
  echo "Installed OpenCode server config and systemd user template."
}

systemctl_all() {
  local number
  for number in $(seq 1 "$SERVER_COUNT"); do
    systemctl --user "$@" "opencode-server@$number.service"
  done
}

status_all() {
  systemctl --user --no-pager --plain status opencode-server@{1..5}.service || true
}

logs_one() {
  local number="$1"
  require_server_number "$number"
  journalctl --user -u "opencode-server@$number.service" -f
}

with_server_env() {
   local number="$1"
   require_server_number "$number"
   local file="$(env_file "$number")"
   if [ -f "$file" ]; then
     set -a
     # shellcheck disable=SC1090
     . "$file"
     set +a
   fi
   export XDG_CONFIG_HOME="$BASE_CONFIG/server-$number/config"
   export XDG_DATA_HOME="$BASE_DATA/server-$number/data"
   export XDG_STATE_HOME="$BASE_STATE/server-$number/state"
   export XDG_CACHE_HOME="$BASE_DATA/server-$number/cache"
   export OPENCODE_TEST_HOME="$BASE_DATA/server-$number/home"
   export OPENCODE_CLIENT="opencode-server-$number"
   export OPENCODE_CONFIG="$XDG_CONFIG_HOME/opencode.json"
   mkdir -p "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$XDG_STATE_HOME" "$XDG_CACHE_HOME" "$OPENCODE_TEST_HOME" "$RAHULOS_VAULT" "$RAHULOS_WORKSPACE"
   
   # Ensure each server has its own copy of the shared config
   if [ ! -f "$OPENCODE_CONFIG" ]; then
     mkdir -p "$(dirname "$OPENCODE_CONFIG")"
     cp "$SHARED_CONFIG" "$OPENCODE_CONFIG" 2>/dev/null || true
   fi
 }

serve_one() {
  local number="$1"
  require_server_number "$number"
  with_server_env "$number"
  local port="${OPENCODE_SERVER_PORT:-$(port_for "$number")}"
  exec "$OPENCODE_BIN" serve --hostname 127.0.0.1 --port "$port"
}

login_one() {
  local number="$1"
  shift || true
  require_server_number "$number"
  with_server_env "$number"
  exec "$OPENCODE_BIN" providers login "$@"
}

attach_one() {
  local number="$1"
  shift || true
  require_server_number "$number"
  local port username password
  port="$(port_for "$number")"
  username="$(awk -F= '$1=="OPENCODE_SERVER_USERNAME" {print $2}' "$(env_file "$number")")"
  password="$(awk -F= '$1=="OPENCODE_SERVER_PASSWORD" {print $2}' "$(env_file "$number")")"
  exec "$OPENCODE_BIN" attach "http://127.0.0.1:$port" --dir "$RAHULOS_VAULT" --username "$username" --password "$password" "$@"
}

print_desktop() {
  local number port file username password
  for number in $(seq 1 "$SERVER_COUNT"); do
    port="$(port_for "$number")"
    file="$(env_file "$number")"
    username="opencode"
    password="<run opencode-servers passwords>"
    if [ -f "$file" ]; then
      username="$(awk -F= '$1=="OPENCODE_SERVER_USERNAME" {print $2}' "$file")"
      password="$(awk -F= '$1=="OPENCODE_SERVER_PASSWORD" {print $2}' "$file")"
    fi
    cat <<ENTRY
OpenCode Server $number
  Server address: http://127.0.0.1:$port
  Server name: OpenCode Server $number
  Username: $username
  Password: $password
ENTRY
  done
}

cmd="${1:-}"
case "$cmd" in
  install) install_all ;;
  start) systemctl_all enable --now ;;
  stop) systemctl_all stop ;;
  restart) systemctl_all restart ;;
  status) status_all ;;
  logs) shift; logs_one "${1:-}" ;;
  login) shift; number="${1:-}"; shift || true; login_one "$number" "$@" ;;
  attach) shift; number="${1:-}"; shift || true; attach_one "$number" "$@" ;;
  serve) shift; serve_one "${1:-}" ;;
  print-desktop|passwords) print_desktop ;;
  -h|--help|help|"") usage ;;
  *) echo "Unknown command: $cmd" >&2; usage; exit 2 ;;
esac
MANAGER_EOF

    chmod 755 "$MANAGER"
    printf "%b\n" "${GREEN}[✓] Manager installed: $MANAGER${RC}"
}

install_servers() {
    printf "\n%b\n" "${CYAN}━━━ OpenCode Servers ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RC}"
    "$MANAGER" install
    "$MANAGER" start
}

verify_servers() {
    printf "\n%b\n" "${CYAN}━━━ Verification ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RC}"
    bash -n "$MANAGER"
    "$MANAGER" status >/dev/null 2>&1 || true

    for port in 4096 4097 4098 4099 4100; do
        server_number=$((port - 4095))
        env_file="$HOME/.config/opencode-servers/server-$server_number/server.env"
        if command_exists curl; then
            username="opencode"
            password=""
            if [ -f "$env_file" ]; then
                username="$(awk -F= '$1=="OPENCODE_SERVER_USERNAME" {print $2}' "$env_file")"
                password="$(awk -F= '$1=="OPENCODE_SERVER_PASSWORD" {print $2}' "$env_file")"
            fi

            if curl -fsS -u "$username:$password" "http://127.0.0.1:$port/health" >/dev/null 2>&1; then
                printf "%b\n" "${GREEN}[✓] OpenCode server listening on 127.0.0.1:$port${RC}"
            else
                printf "%b\n" "${YELLOW}[~] Could not verify health on 127.0.0.1:$port. Check: opencode-servers logs $server_number${RC}"
            fi
        fi
    done

    printf "%b\n" "${GREEN}=================================================================${RC}"
    printf "%b\n" "${GREEN}  OpenCode Servers 1-5 setup complete.${RC}"
    printf "%b\n" "${CYAN}  Status:    opencode-servers status${RC}"
    printf "%b\n" "${CYAN}  Passwords: opencode-servers passwords${RC}"
    printf "%b\n" "${CYAN}  Attach:    opencode-servers attach 1${RC}"
    printf "%b\n" "${CYAN}  Login:     opencode-servers login 1${RC}"
    printf "%b\n" "${GREEN}=================================================================${RC}"
}

install_dependencies
install_opencode_cli
write_manager
install_servers
verify_servers
