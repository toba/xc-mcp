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
COMMITS=(  99484408ca50d28f01363af45e3697c24bad412d        f73a2fcb60198ef2b92dc3b6074b18f98ccee875        22a472ced4c621a0e41b982a6f32dec868d09392)

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
  git clone --filter=blob:none --no-single-branch "$url" "$dest"
  git -C "$dest" checkout "$sha"
  echo "ok: $name at $sha"
done

# IceCubesApp requires an xcconfig (gitignored); create from template if missing
ICE_XCCONFIG="$REPOS_DIR/IceCubesApp/IceCubesApp.xcconfig"
ICE_TEMPLATE="$REPOS_DIR/IceCubesApp/IceCubesApp.xcconfig.template"
if [ ! -f "$ICE_XCCONFIG" ] && [ -f "$ICE_TEMPLATE" ]; then
  cp "$ICE_TEMPLATE" "$ICE_XCCONFIG"
  echo "ok: created IceCubesApp.xcconfig from template"
fi

# Alamofire 5.11.1 has bugs exposed by Xcode 26's stricter Swift compiler:
# 1. `if case let .failure(error)` shadows self.error; assignment to `error`
#    is rejected as assigning to a `let` constant. Fix: use `self.error`.
# 2. `downloadProgress`/`uploadProgress` closures escape but aren't marked
#    `@escaping`. Fix: add `@escaping`.
patch_alamofire() {
  local af="$REPOS_DIR/Alamofire"
  [ -d "$af" ] || return

  # Fix 1: self.error shadowing in validate() closures
  # In Xcode 26, `if case let .failure(error)` shadows self.error; the compiler
  # rejects the binding as reassignment to a `let` constant. Fix: rename binding.
  # All three files have the same single-line format on a clean clone.
  python3 -c "
af = '$af'
import os

for fname in ['DataRequest.swift', 'DataStreamRequest.swift', 'DownloadRequest.swift']:
    f = os.path.join(af, 'Source/Core', fname)
    with open(f) as fh: s = fh.read()
    s = s.replace(
        'if case let .failure(error) = result {\n                self.error = error.asAFError(or: .responseValidationFailed(reason: .customValidationFailed(error: error)))',
        'if case let .failure(validationError) = result {\n                self.error = validationError.asAFError(or: .responseValidationFailed(reason: .customValidationFailed(error: validationError)))'
    )
    with open(f, 'w') as fh: fh.write(s)
"

  # Fix 2: @escaping on ProgressHandler closures
  if grep -q 'public func downloadProgress(queue: DispatchQueue = .main, closure: ProgressHandler)' "$af/Source/Core/Request.swift" 2>/dev/null; then
    sed -i '' \
      's/public func downloadProgress(queue: DispatchQueue = .main, closure: ProgressHandler)/public func downloadProgress(queue: DispatchQueue = .main, closure: @escaping ProgressHandler)/' \
      "$af/Source/Core/Request.swift"
    sed -i '' \
      's/public func uploadProgress(queue: DispatchQueue = .main, closure: ProgressHandler)/public func uploadProgress(queue: DispatchQueue = .main, closure: @escaping ProgressHandler)/' \
      "$af/Source/Core/Request.swift"
  fi

  echo "ok: patched Alamofire for Xcode 26 compatibility"
}
patch_alamofire

# SwiftFormat 0.59.1 (22a472c) compiles cleanly with Xcode 26.
# The previous pin (0.55.3 develop, 2d1b035) had 3 compilation errors from
# Swift 6.2 changes (removeTokens range type, Range.split, AutoUpdatingIndex).
# No patches needed.

echo ""
echo "All fixtures ready in $REPOS_DIR"
