#!/bin/sh -e

echo "==========================================="
echo "   GitHub SSH Key Setup & Verification     "
echo "==========================================="
echo ""

# Function to check if connected to GitHub
check_github_ssh() {
    # ssh -T returns 1 on success for GitHub, or 255 on failure
    if ssh -T git@github.com 2>&1 | grep -q "successfully authenticated"; then
        return 0
    else
        return 1
    fi
}

if check_github_ssh; then
    echo "✅ Your GitHub account is already connected via SSH!"
    exit 0
fi

echo "❌ GitHub SSH connection not found or not authenticated."

# Generate key if it doesn't exist
KEY_FILE="$HOME/.ssh/id_ed25519"
if [ ! -f "$KEY_FILE" ]; then
    echo "Generating new Ed25519 SSH key..."
    printf "Enter your GitHub email: "
    read -r EMAIL
    mkdir -p "$HOME/.ssh"
    ssh-keygen -t ed25519 -C "$EMAIL" -f "$KEY_FILE" -N ""
else
    echo "✅ SSH key already exists at $KEY_FILE. Re-using existing key."
fi

# Start ssh-agent and add key
eval "$(ssh-agent -s)" >/dev/null 2>&1 || true
ssh-add "$KEY_FILE" >/dev/null 2>&1 || true

echo ""
echo "=========================================================="
echo "Your public key (copy the line below):"
echo ""
cat "$KEY_FILE.pub"
echo ""
echo "Go to https://github.com/settings/keys"
echo "Click 'New SSH key', paste your key, and save."
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
