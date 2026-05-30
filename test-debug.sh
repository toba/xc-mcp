#!/bin/bash
# Test harness for xc-debug MCP server tools
#
# Modes:
#   build      - Build and launch under LLDB (default)
#   screenshot - Build, launch, enable view borders, take screenshot
#   evaluate   - Build, launch WITHOUT stop_at_entry, then immediately fire
#                debug_evaluate to reproduce t57-a7q (first-call timeout)
#
# Usage:
#   ./test-debug.sh <project_path> <scheme> [mode] [timeout]
#
# Examples:
#   ./test-debug.sh /Users/jason/Developer/toba/thesis/Thesis.xcodeproj Standard
#   ./test-debug.sh /Users/jason/Developer/toba/thesis/Thesis.xcodeproj Standard screenshot
#   ./test-debug.sh /Users/jason/Developer/toba/thesis/Thesis.xcodeproj Standard build 300

set -euo pipefail

# Special PROJECT value `t57-fixture` scaffolds a tiny self-contained SwiftUI app
# under /tmp so the t57-a7q reproducer doesn't depend on any external project
# being in a buildable state.
#
# Special PROJECT value `lul-evz-fixture` scaffolds the same project shape but
# overwrites the generated App.swift with a "non-trivial" host app: it opens
# multiple NSWindows on launch, spawns background queues that DispatchQueue.main
# .sync chatter against AppKit, and keeps the main runloop busy. The original
# trivial SwiftUI app does NOT reproduce lul-evz — the auto-interrupt lands
# cleanly. This busier app is meant to land the interrupt mid-syscall (the
# Thesis-shape failure mode) so the subsequent `expr -l objc` against
# [[NSApp windows] count] hangs without ever returning a (lldb) prompt.
if [ "${1:-}" = "t57-fixture" ]; then
    PROJECT=".build/t57-fixture/T57Fixture/T57Fixture.xcodeproj"
    SCHEME="T57Fixture"
    MODE="${2:-evaluate}"
    TIMEOUT="${3:-240}"
elif [ "${1:-}" = "lul-evz-fixture" ]; then
    PROJECT=".build/lul-evz-fixture/LulEvzFixture/LulEvzFixture.xcodeproj"
    SCHEME="LulEvzFixture"
    MODE="${2:-evaluate}"
    TIMEOUT="${3:-240}"
else
    PROJECT="${1:?Usage: $0 <project_path> <scheme> [mode] [timeout]  |  $0 t57-fixture [mode] [timeout]}"
    SCHEME="${2:?Usage: $0 <project_path> <scheme> [mode] [timeout]}"
    MODE="${3:-build}"
    TIMEOUT="${4:-240}"
fi

SAVE_PATH="/tmp/xc-debug-screenshot.png"

echo "=== xc-debug test harness ==="
echo "Project: $PROJECT"
echo "Scheme:  $SCHEME"
echo "Mode:    $MODE"
echo "Timeout: ${TIMEOUT}s"
echo ""

# Build first. The focused servers are dispatched from the single multicall
# `xc-mcp` binary via argv[0], so build that product and invoke it through an
# `xc-debug`-named symlink.
echo "Building xc-debug..."
swift build --product xc-mcp 2>&1 | tail -1
ln -sf xc-mcp .build/debug/xc-debug

# Use the monolithic xc-mcp binary so scaffolding tools (xc-build) are available
# alongside the xc-debug tools in a single session. The LLDB code path is shared,
# so this faithfully exercises the same runner the focused server uses.
BINARY=".build/debug/xc-mcp"
if [ "${1:-}" != "t57-fixture" ] && [ "${1:-}" != "lul-evz-fixture" ]; then
    BINARY=".build/debug/xc-debug"
fi
if [ ! -x "$BINARY" ]; then
    echo "ERROR: $BINARY not found"
    exit 1
fi

# Create named pipe for MCP stdin
FIFO=$(mktemp -u /tmp/mcp_test.XXXXXX)
mkfifo "$FIFO"

# Output files
STDOUT_FILE=$(mktemp /tmp/mcp_stdout.XXXXXX)
STDERR_FILE=$(mktemp /tmp/mcp_stderr.XXXXXX)

cleanup() {
    # Kill the inferior before tearing down the server so a fixture app (which
    # `debug_continue` left running) doesn't keep leaking windows on the desktop
    # after the harness exits. The MCP server only owns the LLDB session, not
    # the inferior — once LLDB detaches/dies the app keeps going.
    if [ -n "${PID:-}" ]; then
        kill -9 "$PID" 2>/dev/null || true
    fi
    exec 3>&- 2>/dev/null || true
    rm -f "$FIFO"
    kill "$SERVER_PID" 2>/dev/null || true
    # Copy stderr for post-mortem debugging
    cp "$STDERR_FILE" /tmp/xc-debug-last-stderr.log 2>/dev/null || true
    rm -f "$STDOUT_FILE" "$STDERR_FILE"
}
trap cleanup EXIT

# Start MCP server (--verbose enables debug-level LLDB I/O logging for the
# bug-diagnosis path).
if [ -n "${VERBOSE:-}" ]; then
    "$BINARY" --verbose < "$FIFO" > "$STDOUT_FILE" 2>"$STDERR_FILE" &
else
    "$BINARY" < "$FIFO" > "$STDOUT_FILE" 2>"$STDERR_FILE" &
fi
SERVER_PID=$!

# Open write fd to the pipe
exec 3>"$FIFO"

MSG_ID=0

# Helper: send a JSON-RPC message
send() {
    echo "$1" >&3
}

# Helper: wait for a response with given id
wait_for_response() {
    local msg_id="$1"
    local label="$2"
    local timeout_secs="${3:-$TIMEOUT}"
    local start_time=$(date +%s)

    echo "Waiting for $label (timeout: ${timeout_secs}s)..."
    for i in $(seq 1 "$timeout_secs"); do
        sleep 1

        if ! kill -0 "$SERVER_PID" 2>/dev/null; then
            echo "Server exited unexpectedly"
            echo "=== STDERR ==="
            tail -20 "$STDERR_FILE"
            return 1
        fi

        if grep -q "\"id\":$msg_id" "$STDOUT_FILE" 2>/dev/null; then
            local elapsed=$(($(date +%s) - start_time))
            echo "Got $label response after ${elapsed}s"
            return 0
        fi

        if (( i % 10 == 0 )); then
            echo "  ...${i}s"
        fi
    done

    echo "TIMEOUT waiting for $label"
    echo "=== STDERR ==="
    tail -20 "$STDERR_FILE"
    return 1
}

# Helper: extract text content from response
extract_text() {
    local msg_id="$1"
    grep "\"id\":$msg_id" "$STDOUT_FILE" | jq -r '.result.content[]? | select(.type == "text") | .text' 2>/dev/null
}

# Helper: extract raw response
extract_raw() {
    local msg_id="$1"
    grep "\"id\":$msg_id" "$STDOUT_FILE" 2>/dev/null
}

# Helper: check for error in response. Returns 0 on success, 1 on error.
check_error() {
    local msg_id="$1"
    local label="$2"
    local raw
    raw=$(extract_raw "$msg_id")

    local error
    error=$(echo "$raw" | jq -r '.error // empty' 2>/dev/null)
    if [ -n "$error" ]; then
        echo "ERROR in $label:"
        echo "$raw" | jq '.error'
        return 1
    fi

    local is_error
    is_error=$(echo "$raw" | jq -r '.result.isError // false' 2>/dev/null)
    if [ "$is_error" = "true" ]; then
        echo "TOOL ERROR in $label:"
        extract_text "$msg_id"
        return 1
    fi
    return 0
}

# Helper: send a tool call and wait for response
call_tool() {
    local tool_name="$1"
    local arguments="$2"
    local timeout_secs="${3:-$TIMEOUT}"

    MSG_ID=$((MSG_ID + 1))
    echo ""
    echo "=== $tool_name (id=$MSG_ID) ==="
    send '{"jsonrpc":"2.0","id":'"$MSG_ID"',"method":"tools/call","params":{"name":"'"$tool_name"'","arguments":'"$arguments"'}}'

    if ! wait_for_response $MSG_ID "$tool_name" "$timeout_secs"; then
        return 1
    fi
    if ! check_error $MSG_ID "$tool_name"; then
        return 1
    fi
    echo "--- result ---"
    extract_text $MSG_ID
    echo ""
    return 0
}

# ---- Initialize ----
MSG_ID=$((MSG_ID + 1))
send '{"jsonrpc":"2.0","id":'"$MSG_ID"',"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test-harness","version":"1.0"}}}'
sleep 0.3
send '{"jsonrpc":"2.0","method":"notifications/initialized"}'
sleep 0.5
echo "Initialized."

# ---- Optional: scaffold a minimal fixture project so the repro doesn't
# depend on an external (and potentially broken) project's source state. ----
if [ "${1:-}" = "t57-fixture" ] && [ ! -d "$PROJECT" ]; then
    FIXTURE_DIR=$(dirname "$(dirname "$PROJECT")")
    mkdir -p "$FIXTURE_DIR"
    echo "Scaffolding t57-fixture project at $FIXTURE_DIR ..."
    call_tool "scaffold_macos_project" \
        '{"project_name":"T57Fixture","path":"'"$FIXTURE_DIR"'","bundle_identifier":"com.xcmcp.t57","include_tests":false}' \
        60 || exit 1
fi

if [ "${1:-}" = "lul-evz-fixture" ]; then
    FIXTURE_DIR=$(dirname "$(dirname "$PROJECT")")
    mkdir -p "$FIXTURE_DIR"
    if [ ! -d "$PROJECT" ]; then
        echo "Scaffolding lul-evz-fixture project at $FIXTURE_DIR ..."
        call_tool "scaffold_macos_project" \
            '{"project_name":"LulEvzFixture","path":"'"$FIXTURE_DIR"'","bundle_identifier":"com.xcmcp.lulevz","include_tests":false}' \
            60 || exit 1
    fi

    # (Re-)write the scaffold's trivial App.swift with a non-trivial host that
    # opens many NSWindows, spawns background work that hammers main via
    # DispatchQueue.main.sync, and keeps the main runloop in a busy state so
    # an auto-interrupt lands mid-syscall.
    APP_SWIFT="$FIXTURE_DIR/LulEvzFixture/LulEvzFixture/LulEvzFixtureApp.swift"
    cat > "$APP_SWIFT" <<'SWIFT'
import SwiftUI
import AppKit

@main
struct LulEvzFixtureApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    var body: some Scene {
        WindowGroup("Main") { ContentView() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var extraWindows: [NSWindow] = []
    var heartbeat: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Open several extra NSWindows so [[NSApp windows] count] has to walk
        // a non-trivial list and the AppKit window list is live.
        for i in 0..<6 {
            let w = NSWindow(
                contentRect: NSRect(x: 100 + i * 30, y: 100 + i * 30, width: 320, height: 200),
                styleMask: [.titled, .closable, .resizable],
                backing: .buffered, defer: false
            )
            w.title = "Extra \(i)"
            w.contentView = NSHostingView(rootView: Text("Window \(i)"))
            w.makeKeyAndOrderFront(nil)
            extraWindows.append(w)
        }

        // Park the main thread inside a long sleep syscall so an injected
        // AppKit expression (which must run on main) can't make progress.
        // This mimics Thesis's startup, where the main thread sits in
        // mach_msg2_trap during TCC preflight when auto-interrupt fires.
        Thread.detachNewThread {
            while true { Thread.sleep(forTimeInterval: 60) }
        }
        DispatchQueue.main.async {
            // Long-blocking syscall on the main thread.
            Thread.sleep(forTimeInterval: 3600)
        }
    }
}
SWIFT
    echo "Wrote non-trivial App.swift to $APP_SWIFT"
fi

# ---- Build and launch ----
# evaluate mode wants a running target so we can reproduce the first-call
# timeout (t57-a7q); other modes still want the inferior parked at entry.
STOP_AT_ENTRY="true"
if [ "$MODE" = "evaluate" ]; then
    STOP_AT_ENTRY="false"
fi
SKIP_BUILD="false"
if [ -n "${REPRO_SKIP_BUILD:-}" ]; then
    SKIP_BUILD="true"
fi
call_tool "build_debug_macos" \
    '{"project_path":"'"$PROJECT"'","scheme":"'"$SCHEME"'","stop_at_entry":'"$STOP_AT_ENTRY"',"skip_build":'"$SKIP_BUILD"'}' \
    "$TIMEOUT" || exit 1

# Extract PID from response
PID=$(extract_text $MSG_ID | grep -oE 'PID:?\s*[0-9]+' | grep -oE '[0-9]+' | head -1)
echo "Extracted PID: ${PID:-unknown}"

if [ "$MODE" = "build" ]; then
    echo ""
    echo "=== BUILD COMPLETE ==="
    echo "App launched under LLDB, stopped at entry."
    if [ -n "$PID" ]; then
        echo "PID: $PID"
        echo ""
        echo "To continue: send debug_continue with pid=$PID"
    fi

    echo ""
    echo "=== LAST 10 LINES OF SERVER LOG ==="
    tail -10 "$STDERR_FILE"
    exit 0
fi

if [ "$MODE" = "screenshot" ]; then
    # Continue to let app launch
    PID_ARG=""
    if [ -n "$PID" ]; then
        PID_ARG='"pid":'"$PID"','
    fi

    call_tool "debug_continue" "{${PID_ARG}}" 30 || exit 1

    echo "Waiting 5s for app UI to render..."
    sleep 5

    # Interrupt process to inject view borders
    call_tool "debug_lldb_command" \
        "{${PID_ARG}\"command\":\"process interrupt\"}" 30 || exit 1

    sleep 1

    # Enable view borders
    call_tool "debug_view_borders" \
        "{${PID_ARG}\"enabled\":true,\"color\":\"cyan\",\"border_width\":2}" 30 || exit 1

    # Continue to let borders render
    call_tool "debug_continue" "{${PID_ARG}}" 30 || exit 1

    echo "Waiting 3s for borders to render..."
    sleep 3

    # Take screenshot — extract bundle ID from build response
    BUNDLE_ID=$(extract_text 2 | grep -oE 'Bundle ID: [^ ]+' | sed 's/Bundle ID: //' || echo "")
    if [ -n "$BUNDLE_ID" ]; then
        echo "Using bundle_id: $BUNDLE_ID"
        call_tool "screenshot_mac_window" \
            '{"bundle_id":"'"$BUNDLE_ID"'","save_path":"'"$SAVE_PATH"'"}' 30 || exit 1
    else
        echo "Using app_name: $SCHEME"
        call_tool "screenshot_mac_window" \
            '{"app_name":"'"$SCHEME"'","save_path":"'"$SAVE_PATH"'"}' 30 || exit 1
    fi

    echo ""
    echo "=== SCREENSHOT COMPLETE ==="
    if [ -f "$SAVE_PATH" ]; then
        echo "Saved to: $SAVE_PATH"
        ls -lh "$SAVE_PATH"
    else
        echo "WARNING: Screenshot file not found at $SAVE_PATH"
    fi

    echo ""
    echo "=== LAST 10 LINES OF SERVER LOG ==="
    tail -10 "$STDERR_FILE"
    exit 0
fi

if [ "$MODE" = "evaluate" ]; then
    PID_ARG=""
    if [ -n "$PID" ]; then
        PID_ARG='"pid":'"$PID"','
    fi

    echo ""
    echo "=== t57-a7q REPRO ==="
    echo "Firing debug_evaluate immediately against freshly-launched, running PID $PID"
    echo "(no warmup, no prior debug calls — this is the documented repro)"
    echo ""

    if [ "${REPRO_PRE_DELAY:-0}" != "0" ]; then
        echo "Sleeping ${REPRO_PRE_DELAY}s before first evaluate (REPRO_PRE_DELAY)..."
        sleep "$REPRO_PRE_DELAY"
    fi

    if [ -n "${REPRO_WARMUP:-}" ]; then
        echo "Issuing warmup tool call: $REPRO_WARMUP"
        call_tool "$REPRO_WARMUP" "{${PID_ARG}}" 30 || true
    fi


    # Use a deliberately short per-call timeout so we don't sit through the full
    # 30s LLDB read-timeout if the bug fires. 45s is plenty of headroom for a
    # healthy first-call objc expr against `[[NSApp windows] count]`.
    if call_tool "debug_evaluate" \
        "{${PID_ARG}\"language\":\"objc\",\"expression\":\"(int)[[NSApp windows] count]\",\"object_description\":false}" \
        45
    then
        echo ""
        echo "=== REPRO PASS ==="
        echo "First debug_evaluate against fresh launch returned cleanly."
        echo ""

        # Follow-up: ensure the process is still running, not SIGSTOP'd.
        call_tool "debug_process_status" "{${PID_ARG}}" 15 || true

        echo ""
        echo "=== LAST 20 LINES OF SERVER LOG ==="
        tail -20 "$STDERR_FILE"
        exit 0
    else
        echo ""
        echo "=== REPRO HIT ==="
        echo "debug_evaluate failed (likely the t57-a7q timeout)."
        echo ""
        echo "=== process status ==="
        call_tool "debug_process_status" "{${PID_ARG}}" 15 || true
        echo ""
        echo "=== LAST 40 LINES OF SERVER LOG ==="
        tail -40 "$STDERR_FILE"
        exit 2
    fi
fi

echo "ERROR: Unknown mode '$MODE'. Use 'build', 'screenshot', or 'evaluate'."
exit 1
