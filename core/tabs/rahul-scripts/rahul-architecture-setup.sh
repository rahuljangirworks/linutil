#!/bin/sh -e

# Description: Initializes the local environment architecture for Rahul's Second Brain system.

echo "==========================================="
echo "   Setting up Rahul's Architecture...      "
echo "==========================================="
echo ""

# 0. Ensure GitHub SSH is configured before we attempt to clone!
SSH_SETUP_SCRIPT="$(dirname "$0")/rahul-github-ssh-setup.sh"
if [ -x "$SSH_SETUP_SCRIPT" ]; then
    echo "Running GitHub SSH Setup Verification Phase..."
    "$SSH_SETUP_SCRIPT"
else
    echo "⚠️ Cannot find or execute rahul-github-ssh-setup.sh, skipping SSH verification..."
fi

echo "==========================================="
echo "   Resuming Architecture Setup...          "
echo "==========================================="
echo ""

PROJACTS_DIR="$HOME/projacts"

# 1. Create the main projacts directory
echo "Creating $PROJACTS_DIR..."
mkdir -p "$PROJACTS_DIR"

# 2. Create the context subdirectories
echo "Creating context subdirectories..."
mkdir -p "$PROJACTS_DIR/personal-projacts"
mkdir -p "$PROJACTS_DIR/office-projacts"
mkdir -p "$PROJACTS_DIR/client-projacts"

cd "$PROJACTS_DIR" || exit

# 3. Clone the Global Agent Brain (.agent)
if [ ! -d ".agent" ]; then
    echo "Cloning Global Agent Brain (.agent)..."
    git clone git@github.com:rahuljangirworks/.agent.git
else
    echo "Directory .agent already exists, skipping clone."
fi

# 4. Clone the Second Brain Vault (rahul-second-brain)
if [ ! -d "rahul-second-brain" ]; then
    echo "Cloning Second Brain Vault (rahul-second-brain)..."
    git clone git@github.com:rahuljangirworks/rahul-second-brain.git
else
    echo "Directory rahul-second-brain already exists, skipping clone."
fi

echo ""
echo "========================================="
echo "✅ Architecture setup complete!"
echo "Your Second Brain and Agent Workflows"
echo "are now ready to use at: ~/projacts"
echo "========================================="
echo ""
