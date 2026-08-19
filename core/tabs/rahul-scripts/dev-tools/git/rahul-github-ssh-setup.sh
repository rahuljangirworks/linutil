#!/bin/sh -e

echo "==========================================="
echo "   GitHub SSH Key Setup & Verification     "
echo "==========================================="
echo ""

printf "Enter GitHub account name [rahuljangirworks]: "
read -r GITHUB_NAME
GITHUB_NAME="${GITHUB_NAME:-rahuljangirworks}"

printf "Enter server/device name for GitHub title: "
read -r SERVER_NAME
SERVER_NAME="${SERVER_NAME:-$(hostname)}"

KEY_TITLE="${GITHUB_NAME}-${SERVER_NAME}"
KEY_FILE_SAFE=$(printf "%s" "$KEY_TITLE" | tr -cs 'A-Za-z0-9._-' '_' | sed 's/^_*//; s/_*$//')
KEY_FILE="$HOME/.ssh/github_${KEY_FILE_SAFE}_ed25519"
SSH_CONFIG="$HOME/.ssh/config"

# Function to check if connected to GitHub
check_github_ssh() {
    # ssh -T returns 1 on success for GitHub, or 255 on failure
    if ssh -T git@github.com 2>&1 | grep -q "successfully authenticated"; then
        return 0
    else
        return 1
    fi
}

write_github_ssh_config() {
    BEGIN_MARKER="# BEGIN rahul github ssh"
    END_MARKER="# END rahul github ssh"
    mkdir -p "$HOME/.ssh"
    chmod 700 "$HOME/.ssh"
    TMP_CONFIG=$(mktemp "$HOME/.ssh/github_config.XXXXXX")

    touch "$SSH_CONFIG"
    chmod 600 "$SSH_CONFIG"

    awk -v begin="$BEGIN_MARKER" -v end="$END_MARKER" '
        $0 == begin { skip = 1; next }
        $0 == end { skip = 0; next }
        skip != 1 { print }
    ' "$SSH_CONFIG" > "$TMP_CONFIG"

    {
        echo "$BEGIN_MARKER"
        echo "Host github.com"
        echo "    HostName github.com"
        echo "    User git"
        echo "    IdentityFile $KEY_FILE"
        echo "    IdentitiesOnly yes"
        echo "    AddKeysToAgent yes"
        echo "$END_MARKER"
    } >> "$TMP_CONFIG"

    mv "$TMP_CONFIG" "$SSH_CONFIG"
    chmod 600 "$SSH_CONFIG"
    echo "✅ GitHub SSH config points github.com to $KEY_FILE"
}

if [ ! -f "$KEY_FILE" ]; then
    echo "Generating new Ed25519 SSH key..."
    printf "Enter your GitHub email: "
    read -r EMAIL
    mkdir -p "$HOME/.ssh"
    chmod 700 "$HOME/.ssh"
    ssh-keygen -t ed25519 -C "$EMAIL" -f "$KEY_FILE" -N ""
else
    echo "✅ SSH key already exists at $KEY_FILE. Re-using existing key."
fi

write_github_ssh_config

# Start ssh-agent and add key
eval "$(ssh-agent -s)" >/dev/null 2>&1 || true
ssh-add "$KEY_FILE" >/dev/null 2>&1 || true

echo ""
echo "=========================================================="
echo "Suggested GitHub key title:"
echo ""
echo "  $KEY_TITLE"
echo ""
echo "Local key file:"
echo ""
echo "  $KEY_FILE"
echo ""
echo "Your public key (copy the line below):"
echo ""
cat "$KEY_FILE.pub"
echo ""
echo "Go to https://github.com/settings/keys"
echo "Click 'New SSH key', use the suggested title, paste your key, and save."
echo "=========================================================="
echo ""
printf "Press ENTER only AFTER you have saved the key to GitHub... "
read -r DUMMY

# Verify again
echo ""
echo "Verifying connection to GitHub..."
if check_github_ssh; then
    echo "🎉 SUCCESS! You are now securely connected to GitHub via SSH."
else
    echo "❌ Verification failed. Please ensure you pasted the key correctly."
    echo "If the clipboard didn't work, here is your public key. Copy the line below manually:"
    echo ""
    cat "$KEY_FILE.pub"
    echo ""
fi
