#!/usr/bin/env bash
# Build the multicall binary in release mode and install to the Homebrew Cellar,
# same location `brew install` uses. Compatible with `brew upgrade`.
set -euo pipefail

SYMLINKS=(xc-build xc-debug xc-device xc-project xc-simulator xc-strings xc-swift)

bin="$(realpath "$(brew --prefix xc-mcp)/bin")"

cd "$(dirname "$0")/.."

echo "Building release..."
swift build -c release

src="$(swift build -c release --show-bin-path)/xc-mcp"
if [[ ! -f "$src" ]]; then
    echo "  ERROR: xc-mcp not found at $src"
    exit 1
fi

strip -x -o "$bin/xc-mcp" "$src"
echo "  xc-mcp → $bin/xc-mcp"

for name in "${SYMLINKS[@]}"; do
    ln -sf xc-mcp "$bin/$name"
    echo "  $name → $bin/$name (symlink)"
done

echo "Done."
