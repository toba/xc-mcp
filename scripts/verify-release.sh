#!/usr/bin/env bash
# Launch every executable in a staged release and fail when one cannot start.
#
# The multicall binary reads argv[0], so each symlink starts a different server. Running
# every name checks the whole keg rather than xc-mcp alone. The dylib check reports the
# missing library by name, because dyld reports only the first one it fails to find.
#
# The launch needs a host that meets the binary's deployment target. The release builds
# against a newer SDK than any hosted runner runs, so the launch is skipped there and the
# dylib check carries the release on its own.
#
# Usage: verify-release.sh <staged-dir>
set -euo pipefail

# Report the deployment target the linker wrote into the load commands.
binary_minos() {
    otool -l "$1" | awk '/LC_BUILD_VERSION/ { found = 1 } found && $1 == "minos" { print $2; exit }'
}

# True when the first version is no higher than the second.
version_le() {
    [[ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | head -n 1)" == "$1" ]]
}

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
skipped=0
host_os="$(sw_vers -productVersion)"

for path in "$dest"/bin/*; do
    name="$(basename "$path")"

    while read -r dylib; do
        [[ -n "$dylib" ]] || continue
        if [[ ! -f "$dest/lib/${dylib#@rpath/}" ]]; then
            echo "  FAIL $name links $dylib and the release ships no such file"
            failed=1
        fi
    done < <(otool -L "$path" | awk '/@rpath\//{print $1}')

    # dyld refuses a binary built above the host, and the refusal says nothing about the
    # release. Report it as a skip rather than as a defect.
    minos="$(binary_minos "$path")"
    if [[ -n "$minos" ]] && ! version_le "$minos" "$host_os"; then
        echo "  skip $name needs macOS $minos and this host runs macOS $host_os"
        skipped=$((skipped + 1))
        continue
    fi

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

if [[ $skipped -ne 0 ]]; then
    echo "release verification passed, $skipped launch check(s) skipped on macOS $host_os"
else
    echo "release verification passed"
fi
