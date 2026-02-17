#!/usr/bin/env bash
# Fetch open-source repos used by integration tests.
# Idempotent: skips repos already at the pinned commit.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPOS_DIR="$ROOT_DIR/fixtures/repos"

# Parallel arrays
NAMES=(    IceCubesApp                                     Alamofire                                       SwiftFormat)
URLS=(     https://github.com/Dimillian/IceCubesApp.git    https://github.com/Alamofire/Alamofire.git      https://github.com/nicklockwood/SwiftFormat.git)
COMMITS=(  b7886e2d038c2bb04f19f7cf697e0a259c92a0c3        f73a2fcb60198ef2b92dc3b6074b18f98ccee875        22a472ced4c621a0e41b982a6f32dec868d09392)

mkdir -p "$REPOS_DIR"

for i in "${!NAMES[@]}"; do
  name="${NAMES[$i]}"
  url="${URLS[$i]}"
  sha="${COMMITS[$i]}"
  dest="$REPOS_DIR/$name"

  # Check if already at correct commit
  if [ -d "$dest/.git" ]; then
    current_sha="$(git -C "$dest" rev-parse HEAD 2>/dev/null || echo "")"
    if [ "$current_sha" = "$sha" ]; then
      echo "ok: $name already at $sha"
      continue
    fi
    echo "xx: $name at wrong commit, re-cloning"
    rm -rf "$dest"
  fi

  echo ">>: Cloning $name"
  git clone --filter=blob:none "$url" "$dest"
  git -C "$dest" checkout "$sha"
  echo "ok: $name at $sha"
done

echo ""
echo "All fixtures ready in $REPOS_DIR"
