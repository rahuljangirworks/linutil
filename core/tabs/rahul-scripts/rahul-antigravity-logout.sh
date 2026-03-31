#!/bin/bash
# ==============================================================
# Antigravity IDE - Fresh Refresh Script
# ==============================================================
# PRESERVED: conversations, brain, knowledge, annotations,
#            mcp_config.json, user settings.json
# CLEARED:   auth/tokens, caches, machine IDs, telemetry,
#            browser profile, ephemeral data
#
# NOTE: Antigravity is killed at the VERY END so this script
#       can finish completely before IDE closes.
# ==============================================================

ANTIGRAVITY_CONFIG="$HOME/.config/Antigravity"
GEMINI_DIR="$HOME/.gemini/antigravity"
BROWSER_PROFILE="$HOME/.gemini/antigravity-browser-profile"

echo "============================================================"
echo "   Antigravity IDE - Fresh Refresh"
echo "   All your memory (brain/conversations/knowledge) is SAFE"
echo "============================================================"
echo ""
echo "NOTE: Antigravity will be closed at the END of this script."
echo ""

# ----------------------------------------------------------
# Step 1: Backup user settings
# ----------------------------------------------------------
echo "[1/7] Backing up user settings..."
BACKUP_DIR="/tmp/antigravity-refresh-backup-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"

if [ -f "$ANTIGRAVITY_CONFIG/User/settings.json" ]; then
    cp "$ANTIGRAVITY_CONFIG/User/settings.json" "$BACKUP_DIR/settings.json"
    echo "  OK  - Backed up settings.json"
fi
if [ -d "$ANTIGRAVITY_CONFIG/User/snippets" ]; then
    cp -r "$ANTIGRAVITY_CONFIG/User/snippets" "$BACKUP_DIR/snippets"
    echo "  OK  - Backed up snippets/"
fi
if [ -f "$ANTIGRAVITY_CONFIG/User/keybindings.json" ]; then
    cp "$ANTIGRAVITY_CONFIG/User/keybindings.json" "$BACKUP_DIR/keybindings.json"
    echo "  OK  - Backed up keybindings.json"
fi
echo "  Backup dir: $BACKUP_DIR"

# ----------------------------------------------------------
# Step 2: Generate new machine identity UUIDs
# ----------------------------------------------------------
echo ""
echo "[2/7] Generating new machine identity..."

NEW_MACHINE_ID="$(cat /proc/sys/kernel/random/uuid)"
NEW_INSTALL_ID="$(cat /proc/sys/kernel/random/uuid)"

if [ -f "$ANTIGRAVITY_CONFIG/machineid" ]; then
    printf '%s' "$NEW_MACHINE_ID" > "$ANTIGRAVITY_CONFIG/machineid"
    echo "  OK  - New machineid: $NEW_MACHINE_ID"
else
    echo "  SKIP- machineid not found (created on next launch)"
fi

if [ -f "$GEMINI_DIR/installation_id" ]; then
    printf '%s' "$NEW_INSTALL_ID" > "$GEMINI_DIR/installation_id"
    echo "  OK  - New installation_id: $NEW_INSTALL_ID"
else
    echo "  SKIP- installation_id not found (created on next launch)"
fi

# ----------------------------------------------------------
# Step 3: Clear auth, cookies, session data
# ----------------------------------------------------------
echo ""
echo "[3/7] Clearing auth, cookies, and session data..."

rm -rf "$ANTIGRAVITY_CONFIG/Cookies"            2>/dev/null || true
rm -rf "$ANTIGRAVITY_CONFIG/Cookies-journal"    2>/dev/null || true
rm -rf "$ANTIGRAVITY_CONFIG/Local Storage"      2>/dev/null || true
rm -rf "$ANTIGRAVITY_CONFIG/Session Storage"    2>/dev/null || true
rm -rf "$ANTIGRAVITY_CONFIG/WebStorage"         2>/dev/null || true
rm -f  "$ANTIGRAVITY_CONFIG/Network Persistent State" 2>/dev/null || true
rm -f  "$ANTIGRAVITY_CONFIG/TransportSecurity"  2>/dev/null || true
rm -rf "$ANTIGRAVITY_CONFIG/Service Worker"     2>/dev/null || true
rm -f  "$ANTIGRAVITY_CONFIG/DIPS"               2>/dev/null || true
rm -f  "$ANTIGRAVITY_CONFIG/DIPS-wal"           2>/dev/null || true
rm -rf "$ANTIGRAVITY_CONFIG/Trust Tokens"       2>/dev/null || true
rm -f  "$ANTIGRAVITY_CONFIG/Trust Tokens-journal" 2>/dev/null || true
rm -f  "$ANTIGRAVITY_CONFIG/SharedStorage"      2>/dev/null || true
rm -f  "$ANTIGRAVITY_CONFIG/SharedStorage-wal"  2>/dev/null || true
rm -rf "$ANTIGRAVITY_CONFIG/Shared Dictionary"  2>/dev/null || true
rm -rf "$ANTIGRAVITY_CONFIG/blob_storage"       2>/dev/null || true
rm -f  "$ANTIGRAVITY_CONFIG/Preferences"        2>/dev/null || true
rm -f  "$ANTIGRAVITY_CONFIG/code.lock"          2>/dev/null || true

echo "  OK  - Auth, cookies, session/local/web storage cleared."

# ----------------------------------------------------------
# Step 4: Clear all caches
# ----------------------------------------------------------
echo ""
echo "[4/7] Clearing all caches..."

rm -rf "$ANTIGRAVITY_CONFIG/Cache"                2>/dev/null || true
rm -rf "$ANTIGRAVITY_CONFIG/CachedData"           2>/dev/null || true
rm -rf "$ANTIGRAVITY_CONFIG/CachedConfigurations" 2>/dev/null || true
rm -rf "$ANTIGRAVITY_CONFIG/CachedExtensionVSIXs" 2>/dev/null || true
rm -rf "$ANTIGRAVITY_CONFIG/CachedProfilesData"   2>/dev/null || true
rm -rf "$ANTIGRAVITY_CONFIG/Code Cache"           2>/dev/null || true
rm -rf "$ANTIGRAVITY_CONFIG/GPUCache"             2>/dev/null || true
rm -rf "$ANTIGRAVITY_CONFIG/DawnGraphiteCache"    2>/dev/null || true
rm -rf "$ANTIGRAVITY_CONFIG/DawnWebGPUCache"      2>/dev/null || true
rm -rf "$ANTIGRAVITY_CONFIG/VideoDecodeStats"     2>/dev/null || true
rm -rf "$ANTIGRAVITY_CONFIG/Crashpad"             2>/dev/null || true
rm -rf "$ANTIGRAVITY_CONFIG/Dictionaries"         2>/dev/null || true
rm -rf "$ANTIGRAVITY_CONFIG/shared_proto_db"      2>/dev/null || true
rm -rf "$ANTIGRAVITY_CONFIG/logs"                 2>/dev/null || true
rm -rf "$ANTIGRAVITY_CONFIG/Backups"              2>/dev/null || true
rm -f  "$ANTIGRAVITY_CONFIG/languagepacks.json"   2>/dev/null || true

echo "  OK  - All caches, GPU cache, logs, crashpad cleared."

# ----------------------------------------------------------
# Step 5: Reset telemetry IDs and clear auth tokens (SQLite)
# ----------------------------------------------------------
echo ""
echo "[5/7] Resetting telemetry IDs and clearing stored tokens..."

STORAGE_JSON="$ANTIGRAVITY_CONFIG/User/globalStorage/storage.json"
STATE_DB="$ANTIGRAVITY_CONFIG/User/globalStorage/state.vscdb"

if [ -f "$STORAGE_JSON" ] && command -v python3 > /dev/null 2>&1; then
    cp "$STORAGE_JSON" "${STORAGE_JSON}.bak" 2>/dev/null || true
    python3 - << 'PYEOF'
import json, uuid, os

path = os.path.expanduser('~/.config/Antigravity/User/globalStorage/storage.json')
try:
    with open(path, 'r') as f:
        data = json.load(f)
    for key in ['telemetry.machineId','telemetry.macMachineId',
                'telemetry.sqmId','telemetry.devDeviceId']:
        if key in data:
            data[key] = str(uuid.uuid4())
    for key in ['windowsState','windowSplash','windowSplashWorkspaceOverride','backupWorkspaces']:
        data.pop(key, None)
    if 'profileAssociations' in data:
        data['profileAssociations'] = {'workspaces': {}, 'emptyWindows': {}}
    with open(path, 'w') as f:
        json.dump(data, f, indent=4)
    print('  OK  - Telemetry IDs reset, storage.json cleaned.')
except Exception as e:
    print('  WARN- storage.json:', e)
PYEOF
else
    echo "  SKIP- storage.json not found or python3 missing"
fi

if [ -f "$STATE_DB" ] && command -v python3 > /dev/null 2>&1; then
    cp "$STATE_DB" "${STATE_DB}.bak" 2>/dev/null || true
    python3 - << 'PYEOF'
import sqlite3, os

db = os.path.expanduser('~/.config/Antigravity/User/globalStorage/state.vscdb')
try:
    with sqlite3.connect(db, timeout=5) as conn:
        cur = conn.cursor()
        cur.execute("""DELETE FROM ItemTable WHERE
            key LIKE '%auth%' OR key LIKE '%oauth%' OR key LIKE '%token%'
         OR key LIKE '%login%' OR key LIKE '%credential%'
         OR key LIKE '%secret%' OR key LIKE '%github%' OR key LIKE '%google%'""")
        print(f'  OK  - Cleared {cur.rowcount} auth/token rows from state.vscdb.')
        conn.commit()
except Exception as e:
    print('  WARN- state.vscdb:', e)
PYEOF
else
    echo "  SKIP- state.vscdb not found or python3 missing"
fi

rm -rf "$ANTIGRAVITY_CONFIG/User/workspaceStorage" 2>/dev/null || true
rm -rf "$ANTIGRAVITY_CONFIG/User/History"          2>/dev/null || true
echo "  OK  - Workspace storage and edit history cleared."

# ----------------------------------------------------------
# Step 6: Clear ephemeral .gemini data  (NOT memory!)
# ----------------------------------------------------------
echo ""
echo "[6/7] Clearing ephemeral .gemini data..."

rm -rf "$GEMINI_DIR/browser_recordings" 2>/dev/null || true
rm -rf "$GEMINI_DIR/scratch"            2>/dev/null || true
rm -rf "$GEMINI_DIR/playground"         2>/dev/null || true
rm -rf "$GEMINI_DIR/html_artifacts"     2>/dev/null || true
rm -rf "$GEMINI_DIR/implicit"           2>/dev/null || true
rm -rf "$GEMINI_DIR/context_state"      2>/dev/null || true
rm -rf "$GEMINI_DIR/prompting"          2>/dev/null || true
rm -rf "$BROWSER_PROFILE"               2>/dev/null || true

echo "  OK  - Scratch, playground, html_artifacts, browser profile cleared."
echo "  SAFE- conversations/, brain/, knowledge/, annotations/ NOT touched."

# ----------------------------------------------------------
# Step 7: Restore user settings
# ----------------------------------------------------------
echo ""
echo "[7/7] Restoring your user settings..."
mkdir -p "$ANTIGRAVITY_CONFIG/User"

if [ -f "$BACKUP_DIR/settings.json" ]; then
    cp "$BACKUP_DIR/settings.json" "$ANTIGRAVITY_CONFIG/User/settings.json"
    echo "  OK  - settings.json restored"
fi
if [ -d "$BACKUP_DIR/snippets" ]; then
    cp -r "$BACKUP_DIR/snippets" "$ANTIGRAVITY_CONFIG/User/snippets"
    echo "  OK  - snippets/ restored"
fi
if [ -f "$BACKUP_DIR/keybindings.json" ]; then
    cp "$BACKUP_DIR/keybindings.json" "$ANTIGRAVITY_CONFIG/User/keybindings.json"
    echo "  OK  - keybindings.json restored"
fi

# ----------------------------------------------------------
# Clear GNOME Keyring (best effort)
# ----------------------------------------------------------
if command -v secret-tool > /dev/null 2>&1; then
    for service in "antigravity" "Antigravity"; do
        accounts=$(secret-tool search application "$service" 2>/dev/null \
            | grep 'attribute.account:' | awk '{print $2}' || true)
        for account in $accounts; do
            secret-tool clear application "$service" account "$account" 2>/dev/null || true
        done
    done
fi

# ----------------------------------------------------------
# Summary
# ----------------------------------------------------------
echo ""
echo "============================================================"
echo "  REFRESH COMPLETE!"
echo ""
echo "  PRESERVED:"
echo "    brain/, conversations/, knowledge/, annotations/"
echo "    mcp_config.json, settings.json, snippets, keybindings"
echo ""
echo "  CLEARED:"
echo "    Auth/OAuth tokens, cookies, session data"
echo "    Machine ID + Installation ID (new UUIDs)"
echo "    All caches (GPU/Code/Data/Extensions)"
echo "    Telemetry IDs, SQLite tokens, keyring secrets"
echo "    Browser profile, scratch, playground, recordings"
echo ""
echo "  Settings backup saved to: $BACKUP_DIR"
echo "============================================================"
echo ""
echo "Closing Antigravity now... Relaunch and sign in fresh!"
echo "(Your conversations will all still be there)"
echo ""

# Kill Antigravity in a DETACHED background process, then exit 0 cleanly.
# This way linutil sees exit code 0 (SUCCESS) before Antigravity closes.
(sleep 2 && pkill -f "antigravity" 2>/dev/null; pkill -f "Antigravity" 2>/dev/null; true) &
disown

exit 0
