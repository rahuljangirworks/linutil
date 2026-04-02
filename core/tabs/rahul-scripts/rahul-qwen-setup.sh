#!/bin/sh -e
. ../common-script.sh

checkEnv

clear
printf "%b\n" "${CYAN}=================================================================${RC}"
printf "%b\n" "${YELLOW}   Rahul's Qwen Code CLI Setup + AgentRouter (deepseek-v3.2)     ${RC}"
printf "%b\n" "${CYAN}=================================================================${RC}"
echo ""

# Ensure Node/npm is installed
if ! command_exists npm; then
    printf "%b\n" "${YELLOW}npm not found. Installing Node.js & npm via ${PACKAGER}...${RC}"
    case "$PACKAGER" in
        pacman)
            "$ESCALATION_TOOL" "$PACKAGER" -S --needed --noconfirm npm nodejs
            ;;
        apk)
            "$ESCALATION_TOOL" "$PACKAGER" add npm nodejs
            ;;
        xbps-install)
            "$ESCALATION_TOOL" "$PACKAGER" -Sy nodejs
            ;;
        nala|apt-get|apt)
            "$ESCALATION_TOOL" apt-get update
            "$ESCALATION_TOOL" apt-get install -y npm nodejs
            ;;
        dnf|zypper|eopkg)
            "$ESCALATION_TOOL" "$PACKAGER" install -y nodejs npm
            ;;
        *)
            printf "%b\n" "${RED}Could not auto-install npm. Please install Node.js manually.${RC}"
            exit 1
            ;;
    esac
fi

# Check if qwen is already installed
if command_exists qwen; then
    printf "%b\n" "${GREEN}[*] qwen is already installed. Skipping npm installation.${RC}"
else
    printf "%b\n" "${CYAN}[*] Checking npm global permissions...${RC}"
    # Setup safely without sudo if not root
    if [ "$(id -u)" != "0" ]; then
        NPM_GLOBAL="$HOME/.npm-global"
        if [ ! -d "$NPM_GLOBAL" ]; then
            mkdir -p "$NPM_GLOBAL"
            npm config set prefix "$NPM_GLOBAL"
        fi
        export PATH="$NPM_GLOBAL/bin:$PATH"
        npm install -g @qwen-code/qwen-code
    else
        npm install -g @qwen-code/qwen-code
    fi
    printf "%b\n" "${GREEN}[*] Qwen Code CLI installed!${RC}"
fi

echo ""
printf "%b\n" "${YELLOW}Please enter your AgentRouter API Key (sk-...):${RC}"
read -r API_KEY

if [ -z "$API_KEY" ]; then
    printf "%b\n" "${RED}API Key is required! Exiting.${RC}"
    exit 1
fi

printf "%b\n" "${CYAN}[*] Validating API Key with AgentRouter...${RC}"
RESPONSE=$(curl -s https://agentrouter.org/v1/models -H "Authorization: Bearer $API_KEY")

if echo "$RESPONSE" | grep -q "unauthorized_client_error"; then
    printf "%b\n" "${YELLOW}[~] Key accepted (AgentRouter blocks /models endpoint for external clients - this is normal)${RC}"
elif echo "$RESPONSE" | grep -q "invalid\|not found\|token"; then
    printf "%b\n" "${RED}[✗] Invalid API Key! Please verify your key at agentrouter.org/console/token${RC}"
    exit 1
else
    printf "%b\n" "${GREEN}[✓] API Key validated successfully!${RC}"
fi

printf "%b\n" "${CYAN}[*] Configuring /etc/profile.d/agentrouter.sh for GLOBAL system access...${RC}"

NPM_BIN_PATH='$(npm bin -g 2>/dev/null || npm root -g | sed "s|/lib/node_modules||")'

TMP_CONF=$(mktemp)
cat > "$TMP_CONF" << EOF
# AgentRouter + Qwen Code (Global Config)
export OPENAI_API_KEY="$API_KEY"
export OPENAI_BASE_URL="https://agentrouter.org/v1"
export OPENAI_MODEL="deepseek-v3.2"
export PATH="\$PATH:$NPM_BIN_PATH"
EOF

"$ESCALATION_TOOL" mv "$TMP_CONF" /etc/profile.d/agentrouter.sh
"$ESCALATION_TOOL" chmod 644 /etc/profile.d/agentrouter.sh

printf "%b\n" "${CYAN}[*] Adding fallback configuration to ~/.bashrc for non-login shells...${RC}"

# Clean up any previous configuration securely
for rc_file in "$HOME/.bashrc" "$HOME/.zshrc"; do
    if [ -f "$rc_file" ]; then
        sed -i '/OPENAI_API_KEY/d; /OPENAI_BASE_URL/d; /OPENAI_MODEL/d; /AgentRouter + Qwen Code/d' "$rc_file"
        
        # Append new local fallback
        cat >> "$rc_file" << EOF

# AgentRouter + Qwen Code (Fallback)
export OPENAI_API_KEY="$API_KEY"
export OPENAI_BASE_URL="https://agentrouter.org/v1"
export OPENAI_MODEL="deepseek-v3.2"
export PATH="\$PATH:$NPM_BIN_PATH"
EOF
    fi
done

# Source it into current execution context
. /etc/profile.d/agentrouter.sh
export OPENAI_API_KEY="$API_KEY"
export OPENAI_BASE_URL="https://agentrouter.org/v1"
export OPENAI_MODEL="deepseek-v3.2"

echo ""
printf "%b\n" "${GREEN}=================================================================${RC}"
printf "%b\n" "${GREEN}  Success! Qwen Code CLI is installed, and AgentRouter configured.${RC}"
printf "%b\n" "${CYAN}  Model is permanently set to: deepseek-v3.2 for ALL users.${RC}"
echo ""
printf "%b\n" "${YELLOW}  Note: If Qwen doesn't launch, restart the terminal to ensure PATH is loaded.${RC}"
printf "%b\n" "${CYAN}        Simply type 'qwen' to start coding!${RC}"
printf "%b\n" "${GREEN}=================================================================${RC}"
