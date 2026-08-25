#!/usr/bin/env bash
# Stage the release layout that the tarball and the Homebrew keg both use.
#
# The layout is bin/ for the multicall executable and its symlinks, and lib/ for every
# dylib the build produced. Toba Core and Toba Concurrency each declare a dynamic
# library product, so the executable names them through @rpath and dies in dyld when
# they are absent. The staged executable carries an rpath of @loader_path/../lib, which
# resolves from the extracted tarball and from the installed keg alike.
#
# The lib/ directory disappears when the build produces no dylib, so a later move to
# static linking needs no change here.
#
# Usage: stage-release.sh <build-bin-path> <dest-dir>
set -euo pipefail

readonly SYMLINKS=(xc-build xc-debug xc-device xc-project xc-simulator xc-strings xc-swift)

if [[ $# -ne 2 ]]; then
    echo "usage: $(basename "$0") <build-bin-path> <dest-dir>" >&2
    exit 2
fi

src="$1"
dest="$2"

if [[ ! -f "$src/xc-mcp" ]]; then
    echo "error: no xc-mcp executable at $src" >&2
    exit 1
fi

case "$dest" in
    "" | "/" | "$HOME")
        echo "error: refusing to stage into $dest" >&2
        exit 1
        ;;
esac

rm -rf "${dest:?}"
mkdir -p "$dest/bin" "$dest/lib"

strip -x -o "$dest/bin/xc-mcp" "$src/xc-mcp"

for name in "${SYMLINKS[@]}"; do
    ln -sf xc-mcp "$dest/bin/$name"
done

shopt -s nullglob
dylibs=("$src"/*.dylib)
shopt -u nullglob

if [[ ${#dylibs[@]} -eq 0 ]]; then
    rmdir "$dest/lib"
else
    cp "${dylibs[@]}" "$dest/lib/"
    install_name_tool -add_rpath "@loader_path/../lib" "$dest/bin/xc-mcp"
fi

# strip and install_name_tool each invalidate the ad-hoc signature the linker wrote
codesign --force --sign - "$dest/bin/xc-mcp"

echo "staged $dest/bin/xc-mcp with ${#dylibs[@]} dylib(s)"
