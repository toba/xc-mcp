#!/usr/bin/env bash
# Build the multicall binary in release mode and install to the Homebrew Cellar,
# same location `brew install` uses. Compatible with `brew upgrade`.
set -euo pipefail

cd "$(dirname "$0")/.."

keg="$(realpath "$(brew --prefix xc-mcp)")"

echo "Building release..."
swift build -c release

staged="$(mktemp -d)"
trap 'rm -rf "$staged"' EXIT

scripts/stage-release.sh "$(swift build -c release --show-bin-path)" "$staged/dist"
scripts/verify-release.sh "$staged/dist"

# -R keeps the symlinks as symlinks rather than eight copies of the binary
mkdir -p "$keg/bin"
cp -R "$staged/dist/bin/." "$keg/bin/"
if [[ -d "$staged/dist/lib" ]]; then
    mkdir -p "$keg/lib"
    cp "$staged/dist/lib"/*.dylib "$keg/lib/"
fi

echo "Installed to $keg"
