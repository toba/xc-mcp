#!/bin/bash
# Validate j22-xn8 fix (view-hierarchy fputs flush) and probe ng9-bb8
# (skip_build:true relaunch leaves app windowless) against ../thesis TestApp.
#
# Drives the locally-built .build/debug/xc-mcp via JSON-RPC over pipes so the
# v1.78.7 fix is exercised (vs the v1.78.6 brew binary on PATH).

set -euo pipefail

PROJECT="${1:-/Users/jason/Developer/toba/thesis/Thesis.xcodeproj}"
SCHEME="${2:-TestApp}"
TIMEOUT="${3:-600}"

echo "=== validate-j22-xn8 ==="
echo "Project: $PROJECT"
echo "Scheme:  $SCHEME"
echo ""

echo "Building xc-mcp..."
swift build --product xc-mcp 2>&1 | tail -1
ln -sf xc-mcp .build/debug/xc-debug
BINARY=".build/debug/xc-debug"

FIFO=$(mktemp -u /tmp/mcp_valid.XXXXXX)
mkfifo "$FIFO"
STDOUT_FILE=$(mktemp /tmp/mcp_valid_stdout.XXXXXX)
STDERR_FILE=$(mktemp /tmp/mcp_valid_stderr.XXXXXX)

cleanup() {
    if [ -n "${PID:-}" ]; then kill -9 "$PID" 2>/dev/null || true; fi
    exec 3>&- 2>/dev/null || true
    rm -f "$FIFO"
    kill "$SERVER_PID" 2>/dev/null || true
    cp "$STDERR_FILE" /tmp/validate-j22-xn8-stderr.log 2>/dev/null || true
    cp "$STDOUT_FILE" /tmp/validate-j22-xn8-stdout.log 2>/dev/null || true
    rm -f "$STDOUT_FILE" "$STDERR_FILE" "$MSG_ID_FILE"
}
trap cleanup EXIT

"$BINARY" < "$FIFO" > "$STDOUT_FILE" 2>"$STDERR_FILE" &
SERVER_PID=$!
exec 3>"$FIFO"

# Track msg id in a file so it survives subshells used by $(call_tool ...).
MSG_ID_FILE=$(mktemp /tmp/mcp_valid_msgid.XXXXXX)
echo 0 > "$MSG_ID_FILE"
send() { echo "$1" >&3; }

next_id() {
    local n; n=$(cat "$MSG_ID_FILE"); n=$((n + 1)); echo "$n" > "$MSG_ID_FILE"; echo "$n"
}

wait_for_response() {
    local id="$1" label="$2" t="${3:-$TIMEOUT}"
    echo "[wait] $label id=$id (timeout ${t}s)..." >&2
    for i in $(seq 1 "$t"); do
        sleep 1
        if ! kill -0 "$SERVER_PID" 2>/dev/null; then
            echo "[fatal] server died. stderr tail:" >&2; tail -30 "$STDERR_FILE" >&2; return 1
        fi
        if grep -q "\"id\":$id[,}]" "$STDOUT_FILE" 2>/dev/null; then
            echo "[wait]   got response in ${i}s" >&2; return 0
        fi
        if (( i % 30 == 0 )); then echo "[wait]   ${i}s..." >&2; fi
    done
    echo "[timeout] $label" >&2; tail -30 "$STDERR_FILE" >&2; return 1
}

extract_text() {
    grep "\"id\":$1[,}]" "$STDOUT_FILE" | jq -r '.result.content[]? | select(.type == "text") | .text' 2>/dev/null
}

call_tool() {
    local name="$1" args="$2" t="${3:-$TIMEOUT}"
    local id; id=$(next_id)
    echo "==> $name (id=$id)" >&2
    send '{"jsonrpc":"2.0","id":'"$id"',"method":"tools/call","params":{"name":"'"$name"'","arguments":'"$args"'}}'
    wait_for_response "$id" "$name" "$t" || return 1
    extract_text "$id"
}

call_tool_lenient() {
    set +e; call_tool "$@"; local rc=$?; set -e
    return $rc
}

# Initialize
INIT_ID=$(next_id)
send '{"jsonrpc":"2.0","id":'"$INIT_ID"',"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"validate-j22-xn8","version":"1.0"}}}'
sleep 0.3
send '{"jsonrpc":"2.0","method":"notifications/initialized"}'
sleep 0.5
echo "[init] done"

echo ""
echo "############################################"
echo "# Phase 1: full build + launch"
echo "############################################"
LAUNCH1_OUT=$(call_tool "build_debug_macos" \
    "{\"project_path\":\"$PROJECT\",\"scheme\":\"$SCHEME\"}" \
    "$TIMEOUT") || { echo "[abort] initial build failed"; exit 1; }
echo "$LAUNCH1_OUT"

PID=$(echo "$LAUNCH1_OUT" | grep -E "^PID:" | head -1 | awk '{print $2}')
BUNDLE=$(echo "$LAUNCH1_OUT" | grep -E "^Bundle ID:" | head -1 | awk '{print $3}')
echo "[parsed] PID=$PID  BUNDLE=$BUNDLE"

if [ -z "$PID" ]; then echo "[abort] could not parse PID"; exit 1; fi

# Settle, capture initial state
sleep 3
echo ""
echo "[state] ps -p $PID -o state,command:"
ps -p "$PID" -o state,command 2>&1 || echo "  (no process)"
echo ""
echo "[state] lsappinfo info -only pid (matching bundle):"
lsappinfo list 2>/dev/null | grep -A1 -i "$BUNDLE" | head -10 || true

echo ""
echo "############################################"
echo "# Phase 2: bug 2 — deep view_hierarchy walk"
echo "############################################"
echo "Pre-cleaning /tmp/xcmcp-vh-$PID.txt..."
rm -f "/tmp/xcmcp-vh-$PID.txt"

# Use a SwiftUI-heavy class filter + deep depth — exactly the case bug 2 targets
echo "Calling debug_view_hierarchy max_depth:30 class_filter:HostingView ..."
VH_OUT=$(call_tool_lenient "debug_view_hierarchy" \
    "{\"pid\":$PID,\"platform\":\"macos\",\"class_filter\":\"HostingView\",\"max_depth\":30,\"timeout\":20}" \
    60) || echo "[note] debug_view_hierarchy reported error (expected if expr --timeout fired)"
echo "$VH_OUT" | head -20

echo ""
echo "[check] /tmp/xcmcp-vh-$PID.txt:"
if [ -f "/tmp/xcmcp-vh-$PID.txt" ]; then
    SZ=$(wc -l < "/tmp/xcmcp-vh-$PID.txt")
    echo "  EXISTS — $SZ lines"
    head -10 "/tmp/xcmcp-vh-$PID.txt"
    echo "  ✓ bug 2 fix VALIDATED (file present even on timeout)"
else
    echo "  MISSING — bug 2 fix did NOT survive timeout"
fi

echo ""
echo "############################################"
echo "# Phase 3: bug 1 — skip_build:true relaunch repro"
echo "############################################"

# Detach the debugger first so the app keeps running, then kill the app
# externally (the way the reporter did).
echo "[step] detach debugger from PID $PID..."
call_tool_lenient "debug_detach" "{\"pid\":$PID}" 30 || true

echo "[step] killing app externally (pkill -f $BUNDLE)..."
pkill -f "$BUNDLE" 2>/dev/null || true
sleep 2

echo "[state] after kill:"
ps -p "$PID" -o state,command 2>&1 || echo "  (process gone, expected)"

echo ""
echo "[state] lsregister for $BUNDLE BEFORE skip_build relaunch:"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -dump 2>/dev/null \
    | grep -B1 -A8 "bundle id:.*$BUNDLE" | head -40 || echo "  (no record)"

echo ""
echo "[step] build_debug_macos skip_build:true (bug 1 repro)..."
LAUNCH2_OUT=$(call_tool_lenient "build_debug_macos" \
    "{\"project_path\":\"$PROJECT\",\"scheme\":\"$SCHEME\",\"skip_build\":true}" \
    120) || echo "[note] skip_build relaunch reported error"
echo "$LAUNCH2_OUT"

PID2=$(echo "$LAUNCH2_OUT" | grep -E "^PID:" | head -1 | awk '{print $2}')
echo "[parsed] PID2=$PID2"

if [ -n "$PID2" ]; then
    sleep 4
    echo ""
    echo "[state] ps -p $PID2 -o state,command (3s after relaunch):"
    ps -p "$PID2" -o state,command 2>&1 || echo "  (process gone!)"

    echo ""
    echo "[state] lsregister for $BUNDLE AFTER skip_build relaunch:"
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -dump 2>/dev/null \
        | grep -B1 -A8 "bundle id:.*$BUNDLE" | head -40 || echo "  (no record)"

    echo ""
    echo "[check] window count via debug_lldb_command (po [[NSApp windows] count])..."
    call_tool_lenient "debug_lldb_command" \
        "{\"pid\":$PID2,\"command\":\"expr -l objc -- (NSUInteger)[[(NSApplication *)[NSApplication sharedApplication] windows] count]\"}" \
        45 || true

    echo ""
    echo "[check] SwiftUI hierarchy traversal post-skip_build (the real bug 1 check)..."
    rm -f "/tmp/xcmcp-vh-$PID2.txt"
    call_tool_lenient "debug_view_hierarchy" \
        "{\"pid\":$PID2,\"platform\":\"macos\",\"class_filter\":\"HostingView\",\"max_depth\":30,\"timeout\":20}" \
        60 || echo "[note] debug_view_hierarchy errored (timeout expected for SwiftUI-heavy walks)"

    if [ -f "/tmp/xcmcp-vh-$PID2.txt" ]; then
        SZ=$(wc -l < "/tmp/xcmcp-vh-$PID2.txt")
        echo "  /tmp/xcmcp-vh-$PID2.txt EXISTS — $SZ lines"
        head -5 "/tmp/xcmcp-vh-$PID2.txt"
        if [ "$SZ" -gt 0 ]; then
            echo "  ✓ bug 1 did NOT repro — hierarchy traversal works post-skip_build"
        else
            echo "  ✗ file present but empty — bug 1 partial repro"
        fi
    else
        echo "  ✗ no traversal output file — bug 1 REPRODUCED (no window / no view found)"
    fi

    # Also try debug_evaluate on a plain AppKit expression to distinguish
    # "no window" (LaunchServices issue) from "view traversal fails" (LLDB issue).
    echo ""
    echo "[check] plain AppKit eval post-skip_build..."
    call_tool_lenient "debug_lldb_command" \
        "{\"pid\":$PID2,\"command\":\"expr -l objc -- (id)[(NSApplication *)[NSApplication sharedApplication] mainWindow]\"}" \
        30 || true

    echo "[cleanup] kill PID2 $PID2..."
    kill -9 "$PID2" 2>/dev/null || true
fi

echo ""
echo "############################################"
echo "# Done. stderr -> /tmp/validate-j22-xn8-stderr.log"
echo "#       stdout -> /tmp/validate-j22-xn8-stdout.log"
echo "############################################"
