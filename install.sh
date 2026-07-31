#!/bin/bash
#
# Installs BorderMe as a Finder Quick Action for the current user.
#
#     ./install.sh            install or update
#     ./install.sh --uninstall  remove

set -euo pipefail

SOURCE="$(cd -- "$(dirname -- "$0")" && pwd)/BorderMe.workflow"
SERVICES="$HOME/Library/Services"
DEST="$SERVICES/BorderMe.workflow"

remove_existing() {
    # Only ever delete something that is actually a BorderMe bundle.
    if [ -e "$DEST" ]; then
        if [ ! -f "$DEST/Contents/Resources/borderme.sh" ]; then
            echo "error: $DEST exists but is not a BorderMe bundle." >&2
            echo "Move it aside yourself and run this again." >&2
            exit 1
        fi
        rm -rf "$DEST"
    fi
}

refresh_services() {
    # Ask the services system to notice the change. Harmless if it is not
    # there; the Quick Action shows up after a relaunch either way.
    /System/Library/CoreServices/pbs -flush >/dev/null 2>&1 || true
}

if [ "${1:-}" = "--uninstall" ]; then
    remove_existing
    refresh_services
    echo "BorderMe removed."
    exit 0
fi

if [ ! -d "$SOURCE" ]; then
    echo "error: BorderMe.workflow not found next to this script." >&2
    exit 1
fi

if [ ! -x "$SOURCE/Contents/Resources/borderme-engine" ]; then
    echo "error: the image engine is missing. Run ./build.sh first." >&2
    exit 1
fi

mkdir -p "$SERVICES"
remove_existing
cp -R "$SOURCE" "$DEST"

# A bundle downloaded from the internet arrives quarantined, and macOS will
# refuse to run the unsigned engine inside it. Clearing the flag on a copy the
# user has chosen to install is the same consent Finder's own dialog asks for.
xattr -dr com.apple.quarantine "$DEST" 2>/dev/null || true

chmod +x "$DEST/Contents/Resources/borderme-engine" \
         "$DEST/Contents/Resources/borderme.sh"

refresh_services

echo "BorderMe installed to $DEST"
echo
echo "Select images in Finder, right-click, and choose Quick Actions > BorderMe."
echo "If it is not listed, enable it in System Settings > General >"
echo "Login Items & Extensions > Finder extensions."
