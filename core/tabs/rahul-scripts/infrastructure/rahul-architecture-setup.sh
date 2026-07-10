#!/bin/sh -e

# Description: Sets up RahulOS architecture — the vault (~/work/.work/) + workspace (~/work/) + agent symlinks.

echo "==========================================="
echo "   Setting up Rahul's Architecture...      "
echo "   (RahulOS v3.0.0 — Vault + Workspace)   "
echo "==========================================="
echo ""

find_ssh_setup_script() {
    local script_dir
    script_dir="$(CDPATH= cd -- "$(dirname -- "$0")" 2>/dev/null && pwd -P || pwd)"

    for candidate in \
        "$script_dir/../dev-tools/rahul-github-ssh-setup.sh" \
        "$PWD/dev-tools/rahul-github-ssh-setup.sh" \
        "$PWD/core/tabs/rahul-scripts/dev-tools/rahul-github-ssh-setup.sh" \
        "$HOME/work/personal-projacts/linutil/core/tabs/rahul-scripts/dev-tools/rahul-github-ssh-setup.sh" \
        "$HOME/work/linutil/core/tabs/rahul-scripts/dev-tools/rahul-github-ssh-setup.sh"
    do
        if [ -x "$candidate" ]; then
            printf "%s\n" "$candidate"
            return 0
        fi
    done

    return 1
}

ensure_vault_remote() {
    if git -C "$VAULT_DIR" remote get-url origin >/dev/null 2>&1; then
        git -C "$VAULT_DIR" remote set-url origin "$VAULT_REMOTE"
    else
        git -C "$VAULT_DIR" remote add origin "$VAULT_REMOTE"
    fi
}

# ── 0. Ensure GitHub SSH is configured ────────────────────────────────────────
SSH_SETUP_SCRIPT="$(find_ssh_setup_script || true)"
if [ -n "$SSH_SETUP_SCRIPT" ]; then
    echo "[0/5] Running GitHub SSH Setup Verification..."
    "$SSH_SETUP_SCRIPT"
else
    echo "[0/5] ⚠️  rahul-github-ssh-setup.sh not found, skipping SSH verification..."
fi
echo ""

# ── 1. Clone or init the vault (~/work/.work/) ────────────────────────────────
WORK_DIR="$HOME/work"
VAULT_DIR="$WORK_DIR/.work"
VAULT_REMOTE="git@github.com:rahuljangirworks/.work.git"

echo "[1/5] Setting up vault at $VAULT_DIR..."
mkdir -p "$WORK_DIR"

if [ -d "$VAULT_DIR/.git" ]; then
    echo "  Vault already exists, pulling latest..."
    ensure_vault_remote
    cd "$VAULT_DIR" && GIT_TERMINAL_PROMPT=0 git pull --ff-only 2>/dev/null || echo "  ⚠️  Git pull failed (maybe SSH key, access, or uncommitted changes). Continuing..."
elif [ ! -d "$VAULT_DIR" ]; then
    echo "  Cloning vault from $VAULT_REMOTE..."
    git clone "$VAULT_REMOTE" "$VAULT_DIR"
else
    echo "  $VAULT_DIR exists but is not a git repo. Initializing..."
    cd "$VAULT_DIR" && git init && ensure_vault_remote && GIT_TERMINAL_PROMPT=0 git fetch origin main && git checkout main 2>/dev/null || true
fi
echo ""

# ── 2. Create vault directory structure ───────────────────────────────────────
echo "[2/5] Ensuring vault directory structure..."

mkdir -p "$VAULT_DIR/00-soul/data"
mkdir -p "$VAULT_DIR/00-soul/schema"
mkdir -p "$VAULT_DIR/01-inbox"
mkdir -p "$VAULT_DIR/02-office-projacts/_agent"
mkdir -p "$VAULT_DIR/03-client-projacts/_agent"
mkdir -p "$VAULT_DIR/04-personal-projacts/_agent"
mkdir -p "$VAULT_DIR/05-knowledge"
mkdir -p "$VAULT_DIR/06-resources/config"
mkdir -p "$VAULT_DIR/06-resources/git-hooks"
mkdir -p "$VAULT_DIR/06-resources/project-brain/contracts"
mkdir -p "$VAULT_DIR/06-resources/project-brain/recipes"
mkdir -p "$VAULT_DIR/06-resources/scripts"
mkdir -p "$VAULT_DIR/06-resources/skills"
mkdir -p "$VAULT_DIR/06-resources/standards"
mkdir -p "$VAULT_DIR/06-resources/templates/buddy-agent"
mkdir -p "$VAULT_DIR/06-resources/templates/project-agent"
mkdir -p "$VAULT_DIR/07-archive"
mkdir -p "$VAULT_DIR/_agent/memory/daily"
mkdir -p "$VAULT_DIR/_agent/state"
mkdir -p "$VAULT_DIR/_agent/skills"
mkdir -p "$VAULT_DIR/_agent/subagents"
mkdir -p "$VAULT_DIR/_agent/symlink-registry"
mkdir -p "$VAULT_DIR/_agent/workspace"
mkdir -p "$VAULT_DIR/data/mcp"
echo "  ✓ Vault structure ready"
echo ""

# ── 3. Create workspace directories (~/work/) ────────────────────────────────
echo "[3/5] Setting up workspace at ~/work/..."

mkdir -p "$WORK_DIR/personal-projacts"
mkdir -p "$WORK_DIR/office-projacts"
mkdir -p "$WORK_DIR/client-projacts"
echo "  ✓ Workspace directories ready"
echo ""

# ── 4. Create .agent symlinks (workspace → vault) ────────────────────────────
echo "[4/5] Creating .agent symlinks..."

# Root vault pointer
if [ -f "$VAULT_DIR/_agent/AGENTS.md" ]; then
    if [ -L "$VAULT_DIR/AGENTS.md" ] || [ ! -e "$VAULT_DIR/AGENTS.md" ]; then
        ln -sfn "_agent/AGENTS.md" "$VAULT_DIR/AGENTS.md"
        echo "  ✓ vault root AGENTS.md → _agent/AGENTS.md"
    fi
fi

# Scope-level symlinks (workspace dirs → vault scope _agent/)
create_scope_symlink() {
    local workspace_dir="$1"
    local vault_scope_dir="$2"
    local scope_name="$3"

    if [ -d "$workspace_dir" ] && [ -f "$VAULT_DIR/$vault_scope_dir/_agent/AGENTS.md" ]; then
        if [ -L "$workspace_dir/AGENTS.md" ] || [ ! -e "$workspace_dir/AGENTS.md" ]; then
            ln -sfn "../.work/$vault_scope_dir/_agent/AGENTS.md" "$workspace_dir/AGENTS.md" 2>/dev/null || true
            echo "  ✓ $scope_name workspace AGENTS.md linked"
        fi
    fi
}

create_scope_symlink "$WORK_DIR/personal-projacts" "04-personal-projacts" "personal"
create_scope_symlink "$WORK_DIR/office-projacts" "02-office-projacts" "office"
create_scope_symlink "$WORK_DIR/client-projacts" "03-client-projacts" "client"

# Fix machine-specific symlinks using vault's repair script
FIX_SCRIPT="$VAULT_DIR/06-resources/scripts/rahulos-fix-symlinks.sh"
if [ -x "$FIX_SCRIPT" ]; then
    echo "  Running symlink repair..."
    "$FIX_SCRIPT" 2>/dev/null || echo "  ⚠️  Symlink repair had warnings (usually fine on first setup)"
fi
echo "  ✓ Agent symlinks ready"
echo ""

# ── 5. Summary ────────────────────────────────────────────────────────────────
echo "========================================="
echo "✅ RahulOS Architecture setup complete!"
echo ""
echo "  Vault:    $VAULT_DIR"
echo "  Workspace: $WORK_DIR"
echo ""
echo "  Agent hierarchy:"
echo "    Haraka (root orchestrator)  → $VAULT_DIR/_agent/"
echo "    Office Buddy               → $VAULT_DIR/02-office-projacts/_agent/"
echo "    Client Buddy               → $VAULT_DIR/03-client-projacts/_agent/"
echo "    Personal Buddy             → $VAULT_DIR/04-personal-projacts/_agent/"
echo ""
echo "  Start working:  $VAULT_DIR/06-resources/scripts/rahulos-start-work.sh"
echo "  Fix symlinks:   $VAULT_DIR/06-resources/scripts/rahulos-fix-symlinks.sh"
echo "========================================="
echo ""
