#!/usr/bin/env bash
# Launch every executable in a staged release and fail when one cannot start.
#
# The multicall binary reads argv[0], so each symlink starts a different server. Running
# every name checks the whole keg rather than xc-mcp alone. The dylib check reports the
# missing library by name, because dyld reports only the first one it fails to find.
#
# Usage: verify-release.sh <staged-dir>
set -euo pipefail

if [[ $# -ne 1 ]]; then
    echo "usage: $(basename "$0") <staged-dir>" >&2
    exit 2
fi

dest="$1"

if [[ ! -d "$dest/bin" ]]; then
    echo "error: no bin directory in $dest" >&2
    exit 1
fi

failed=0

for path in "$dest"/bin/*; do
    name="$(basename "$path")"

    while read -r dylib; do
        [[ -n "$dylib" ]] || continue
        if [[ ! -f "$dest/lib/${dylib#@rpath/}" ]]; then
            echo "  FAIL $name links $dylib and the release ships no such file"
            failed=1
        fi
    done < <(otool -L "$path" | awk '/@rpath\//{print $1}')

    if output="$("$path" --help 2>&1)"; then
        case "$output" in
            *"MCP server"*) echo "  ok   $name" ;;
            *)
                echo "  FAIL $name started but printed no server description"
                failed=1
                ;;
        esac
    else
        echo "  FAIL $name did not start:"
        while IFS= read -r line; do
            echo "         $line"
        done <<< "$output"
        failed=1
    fi
done

if [[ $failed -ne 0 ]]; then
    echo "release verification failed" >&2
    exit 1
fi

echo "release verification passed"
