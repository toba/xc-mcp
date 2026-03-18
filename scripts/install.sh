#!/bin/bash
# Build the multicall binary in release mode and install to /opt/homebrew/bin,
# same location Homebrew uses. Creates symlinks for focused server variants.
set -euo pipefail

INSTALL_DIR="/opt/homebrew/bin"
SYMLINKS=(xc-build xc-debug xc-device xc-project xc-simulator xc-strings xc-swift)

cd "$(dirname "$0")/.."

echo "Building release..."
swift build -c release

BUILD_DIR=$(swift build -c release --show-bin-path)

src="$BUILD_DIR/xc-mcp"
if [[ ! -f "$src" ]]; then
    echo "  ERROR: xc-mcp not found at $src"
    exit 1
fi

strip -x -o "$INSTALL_DIR/xc-mcp" "$src"
echo "  xc-mcp → $INSTALL_DIR/xc-mcp"

for name in "${SYMLINKS[@]}"; do
    ln -sf "$INSTALL_DIR/xc-mcp" "$INSTALL_DIR/$name"
    echo "  $name → $INSTALL_DIR/$name (symlink)"
done

echo "Done."
