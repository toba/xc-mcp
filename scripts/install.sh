#!/bin/bash
# Build all executables in release mode and install to /opt/homebrew/bin,
# same location Homebrew uses. Skips the brew release cycle entirely.
set -euo pipefail

INSTALL_DIR="/opt/homebrew/bin"
EXECUTABLES=(xc-mcp xc-project xc-simulator xc-device xc-debug xc-swift xc-build xc-strings)

cd "$(dirname "$0")/.."

echo "Building release..."
swift build -c release

BUILD_DIR=$(swift build -c release --show-bin-path)

for exe in "${EXECUTABLES[@]}"; do
    src="$BUILD_DIR/$exe"
    if [[ ! -f "$src" ]]; then
        echo "  SKIP $exe (not found at $src)"
        continue
    fi
    cp "$src" "$INSTALL_DIR/$exe"
    echo "  $exe → $INSTALL_DIR/$exe"
done

echo "Done."
