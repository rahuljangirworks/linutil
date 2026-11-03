#!/bin/sh -e

# Description: Clean reinstall Antigravity (wrapper for rahul-antigravity-setup.sh)
# Works on: Linux x86_64 / aarch64

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
exec "$SCRIPT_DIR/rahul-antigravity-setup.sh" "$@"
