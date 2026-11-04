#!/bin/sh -e

# Description: Install/update Traycer AI Desktop (Delegates to unified rahul-traycer-setup.sh)

case "$0" in
    */*) script_path="$0" ;;
    *) script_path="$(command -v -- "$0" 2>/dev/null || printf "%s\n" "$0")" ;;
esac
SCRIPT_DIR="$(dirname "$script_path")"
SCRIPT_DIR="$(cd "$SCRIPT_DIR" && pwd)"
unset script_path

exec "$SCRIPT_DIR/rahul-traycer-setup.sh" "$@"
