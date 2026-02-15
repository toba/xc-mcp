#!/bin/bash
# Test harness for build_debug_macos tool
# Usage: ./test-debug.sh <project_path> <scheme>
#
# Example:
#   ./test-debug.sh /Users/jason/Developer/toba/thesis/Thesis.xcodeproj Standard

set -euo pipefail

PROJECT="${1:?Usage: $0 <project_path> <scheme>}"
SCHEME="${2:?Usage: $0 <project_path> <scheme>}"
STOP_AT_ENTRY="${3:-true}"
TIMEOUT="${4:-240}"

echo "=== build_debug_macos test harness ==="
echo "Project: $PROJECT"
echo "Scheme:  $SCHEME"
echo "Stop at entry: $STOP_AT_ENTRY"
echo "Timeout: ${TIMEOUT}s"
echo ""

# Build first
echo "Building xc-debug..."
swift build --product xc-debug 2>&1 | tail -1

BINARY=".build/debug/xc-debug"
if [ ! -x "$BINARY" ]; then
    echo "ERROR: $BINARY not found"
    exit 1
fi

# Create named pipe for MCP stdin
FIFO=$(mktemp -u /tmp/mcp_test.XXXXXX)
mkfifo "$FIFO"
trap "rm -f $FIFO; pkill -f 'xc-debug' 2>/dev/null || true" EXIT

# Output files
STDOUT_FILE=$(mktemp /tmp/mcp_stdout.XXXXXX)
STDERR_FILE=$(mktemp /tmp/mcp_stderr.XXXXXX)

# Start MCP server
"$BINARY" < "$FIFO" > "$STDOUT_FILE" 2>"$STDERR_FILE" &
SERVER_PID=$!

# Open write fd to the pipe
exec 3>"$FIFO"

# Send initialize
echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test-harness","version":"1.0"}}}' >&3
sleep 0.3

# Send initialized notification
echo '{"jsonrpc":"2.0","method":"notifications/initialized"}' >&3
sleep 0.5

# Send build_debug_macos tool call
echo "Sending build_debug_macos request..."
START_TIME=$(date +%s)

echo '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"build_debug_macos","arguments":{"project_path":"'"$PROJECT"'","scheme":"'"$SCHEME"'","stop_at_entry":'"$STOP_AT_ENTRY"'}}}' >&3

# Wait for response
echo "Waiting for response (timeout: ${TIMEOUT}s)..."
for i in $(seq 1 "$TIMEOUT"); do
    sleep 1

    if ! kill -0 "$SERVER_PID" 2>/dev/null; then
        ELAPSED=$(($(date +%s) - START_TIME))
        echo "Server exited after ${ELAPSED}s"
        break
    fi

    if grep -q '"id":2' "$STDOUT_FILE" 2>/dev/null; then
        ELAPSED=$(($(date +%s) - START_TIME))
        echo "Got response after ${ELAPSED}s"
        break
    fi

    # Print progress dots
    if (( i % 10 == 0 )); then
        echo "  ...${i}s"
    fi
done

# Close pipe
exec 3>&-

echo ""
echo "=== RESULT ==="

# Pretty-print the tool call response (id:2)
if command -v python3 &>/dev/null; then
    python3 -c "
import json, sys
for line in open('$STDOUT_FILE'):
    try:
        msg = json.loads(line.strip())
        if msg.get('id') == 2:
            if 'result' in msg:
                content = msg['result'].get('content', [])
                for item in content:
                    if item.get('type') == 'text':
                        print('SUCCESS:')
                        print(item['text'])
            elif 'error' in msg:
                print('ERROR:')
                print(json.dumps(msg['error'], indent=2))
            sys.exit(0)
    except: pass
print('No response received for tool call')
" 2>/dev/null
else
    grep '"id":2' "$STDOUT_FILE" || echo "No response found"
fi

echo ""
echo "=== LAST 10 LINES OF SERVER LOG ==="
tail -10 "$STDERR_FILE"

# Cleanup
kill "$SERVER_PID" 2>/dev/null || true
rm -f "$STDOUT_FILE" "$STDERR_FILE"
