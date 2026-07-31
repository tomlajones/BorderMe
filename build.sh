#!/bin/bash
#
# Compiles BorderMe.swift into the universal binary that ships inside
# BorderMe.workflow. Run this after changing BorderMe.swift.
#
# Requires the Xcode command line tools:  xcode-select --install

set -euo pipefail

cd -- "$(dirname -- "$0")"

RESOURCES="BorderMe.workflow/Contents/Resources"
SOURCE="$RESOURCES/BorderMe.swift"
ENGINE="$RESOURCES/borderme-engine"
DEPLOYMENT_TARGET="11.0"

if ! command -v swiftc >/dev/null 2>&1; then
    echo "error: swiftc not found. Install the Xcode command line tools:" >&2
    echo "    xcode-select --install" >&2
    exit 1
fi

STAGING=$(mktemp -d)
trap 'rm -rf "$STAGING"' EXIT

# Build each slice separately, then join them, so the Quick Action runs
# natively on both Apple silicon and Intel Macs.
for ARCH in arm64 x86_64; do
    echo "compiling $ARCH"
    swiftc -O \
        -target "$ARCH-apple-macos$DEPLOYMENT_TARGET" \
        "$SOURCE" \
        -o "$STAGING/borderme-engine-$ARCH"
done

echo "joining slices"
lipo -create \
    "$STAGING/borderme-engine-arm64" \
    "$STAGING/borderme-engine-x86_64" \
    -output "$ENGINE"

# An ad-hoc signature is enough for a binary the user installs themselves.
# Shipping this to other people without an Apple Developer ID means they will
# need to clear the quarantine flag once; install.sh does that for them.
codesign --force --sign - "$ENGINE"

chmod +x "$ENGINE" "$RESOURCES/borderme.sh"

echo
echo "built $ENGINE"
lipo -archs "$ENGINE" | sed 's/^/  architectures: /'
codesign -dv "$ENGINE" 2>&1 | grep -E '^(Format|Signature)' | sed 's/^/  /'
