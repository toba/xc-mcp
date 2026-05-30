---
# q7z-ne0
title: debug_view_hierarchy bounded walk still hangs LLDB on SwiftUI hosting hierarchies even with raised timeout
status: completed
type: bug
priority: normal
created_at: 2026-05-30T01:19:07Z
updated_at: 2026-05-30T02:23:23Z
sync:
    github:
        issue_number: "364"
        synced_at: "2026-05-30T02:27:14Z"
---

Follow-up to eka-s03 / h0c-60y. The h0c-60y fix did flow the user-supplied \`timeout\` through to the embedded LLDB expr (the command now shows \`expr -l objc -O --timeout 60000000 ...\` when called with \`timeout: 60\`, instead of the previous hardcoded 15 s). That part works.

The remaining problem is that the bounded NSView walk itself just doesn't return inside the raised timeout against macOS SwiftUI hierarchies.

## Repro
Same TestApp launch as eka-s03 / h0c-60y (\`thesis\` repo, \`debug_view_hierarchy\` against the Chapter 2 node of the Test_Manuscript fixture). After the app has been up ~4 s:

\`\`\`
mcp__xc-debug__debug_view_hierarchy pid: <pid> platform: macos max_depth: 4 timeout: 60
\`\`\`

First call → \`LLDB session is poisoned by a previous timeout\`. Retry → \`Timed out waiting for LLDB response. Partial output: expr -l objc -O --timeout 60000000 ...\` (the partial output is the head of the same command being built and dispatched, so the expression isn't even returning a partial subview line).

## Why this matters for wis-g7q
The Thesis side (issue \`wis-g7q\`) needs to inspect the outer NSTextView's subview tree at the moment table-cell SwiftUI marks fail to paint. \`max_depth: 4\` is enough to surface the \`PlatformHostingView<TableView>\` and its first level of children — that's at most a few hundred NSViews on a single-column document. Without a working dump there's no way to identify the stranded zombie hosting view.

## Likely cause
The bounded walk's expression builds an Objective-C \`NSMutableString\` line by line for every visited node and returns it as one ObjC value at the end. The LLDB ObjC expression evaluator has to:
- Allocate that NSMutableString in the target process.
- Walk every NSView's class name, frame, and pointer through ObjC messaging.
- Materialize the result back across the LLDB IPC.

Even when the walk would visit only a few hundred nodes, the per-node overhead inside the JIT'd ObjC expression appears to push past 60 s on SwiftUI-heavy windows. Plain \`po contentView\` returns instantly; building a 200-line ObjC accumulator does not.

## Suggested fixes (pick one — the rest can stay future work)

1. **Stream to a host-side file instead of returning a string.** Have the bounded walk fopen a path on the *host* (the LLDB-attached process can write to \`/tmp/<pid>-hierarchy.txt\` via \`fopen\` / \`fwrite\` / \`fclose\` against the target's libc), close it on completion, and return only the path. The tool reads the file from disk. Avoids the LLDB IPC return-value cost entirely.
2. **Page the result.** Add a \`page_size\` and \`page_token\` to \`debug_view_hierarchy\` so the walk returns one chunk per call. Each call's expr only builds a small accumulator. Probably the smallest change.
3. **Run the walk as a Mach helper, not an LLDB expression.** Inject a dylib that performs the walk and writes to a UNIX socket; the tool reads from the socket. Bypasses LLDB's expression evaluator entirely.

## Lower-effort interim
Even just exposing the partial accumulator at the timeout point would be useful — right now the partial-output message only shows the *command*, not any subview lines the walk had already written. If the tool could capture and return whatever lines were generated before the timeout, we'd at least see the top-level NSView class names.

## Reproducer
\`\`\`
mcp__xc-debug__build_debug_macos scheme: TestApp args: [
  "--database", "/tmp/test_manuscript_fixture.sqlite",
  "--show-node", "5B547E2B-172B-42A9-B24B-263B2F6A054F"
]
# wait ~4s
mcp__xc-debug__debug_view_hierarchy pid: <pid> platform: macos max_depth: 4 timeout: 60
\`\`\`

(\`/tmp/test_manuscript_fixture.sqlite\` is produced by the Thesis \`TestApp/FixtureSeeder\` helper from \`Integrations/DocX/Tests/TestData/Test_Manuscript.docx\`.)


## Summary of Changes

Fixed `debug_view_hierarchy` bounded walk against macOS SwiftUI hierarchies. The original diagnosis (NSMutableString accumulator + IPC return cost) turned out to be downstream of two more fundamental problems uncovered by direct LLDB testing against a minimal SwiftUI app:

1. **The bounded-walk expression was failing to compile, not running slowly.** Recent LLDBs silently promote `expr -l objc` to Objective-C++ ("Expression evaluation in pure Objective-C not supported. Ran expression as 'Objective C++'"). In that mode, variadic ObjC method selectors like `appendFormat:` need Foundation in scope to parse beyond a single argument — without `@import Foundation;`, compilation fails with "too many arguments to method call, expected 1, have N". The bounded walk has been silently broken on this LLDB version; the "hang" was xc-debug waiting for a prompt that never came after a compile failure.

2. **The expression was too long to send through LLDB's PTY in raw mode.** Even with imports fixed, the ~2 KB expression ran in 5 s via batch `lldb -p`, but never even started via `xc-debug`'s PTY-backed session — the bytes arrived but lldb never began evaluation. Workaround: write the `expr` command to a temp `.lldb` script and use `command source`, so the PTY only carries the short `command source ...` line.

### Code changes
- `Sources/Core/LLDBRunner.swift`
  - `boundedTraversalExpr`: prepend `@import Darwin; @import Foundation; @import AppKit;` (Darwin brings `<stdio.h>` for `FILE`/`fopen`/`fputs`/`fclose`).
  - New file-streaming variant (`outputPath` arg): per-node lines are formatted as small NSMutableStrings and written to a host-readable `/tmp/xcmcp-vh-<pid>.txt` via libc `fputs`. The expression returns only a tiny status string; the host reads the dump from disk. Avoids both the growing-NSMutableString cost and the IPC return-value cost for very large hierarchies.
  - `viewHierarchy`: on macOS bounded walks, generate the output path, remove any stale file, and read the dump from disk after the expression returns. When the expression command exceeds 512 bytes, route it through a temp `command source` script instead of the direct PTY write.

### Verification
Tested end-to-end against a minimal SwiftUI app (`ScrollView` of 100 rows + `NSTextView` wrapped via `NSViewRepresentable`) through the `xc-debug` MCP server over JSON-RPC:

- Before this fix: `debug_view_hierarchy` with `max_depth: 4` timed out after 60+ s with no output file written.
- After this fix: same call returned in 5 s with the full 11-node hierarchy:
  ```
  <…AppKitWindowHostingView…: 0x…> frame=(0.0, 0.0, 900.0, 632.0)
    <…HostingScrollView.PlatformContainer: 0x…> frame=(66.0, 82.0, 768.0, 326.0)
      …
    <…AppKitPlatformViewHost…TextViewWrapper…: 0x…> frame=(66.0, 416.0, 768.0, 200.0)
      <NSScrollView: 0x…> frame=(0.0, 0.0, 768.0, 200.0)
        <NSClipView: 0x…> frame=(0.0, 0.0, 751.0, 200.0)
          <NSTextView: 0x…> frame=(0.0, 0.0, 751.0, 714.0)
        <NSScroller: 0x…> …
  ```

### Out of scope (follow-up worth filing)
- The crash-warning helper flags any `stopped with signal SIG*` as a crash, including `SIGSTOP` from a fresh `process attach --pid N`. After a successful bounded-walk-on-attached-running-target call, subsequent calls against a *freshly attached* process see "Process is stopped due to a crash (SIGSTOP)" — `withProcessStopped` only resumes the target if *it* was the one that interrupted it. Not exercised by the original repro (Thesis launches the app under LLDB and `view_hierarchy` is called against the same already-attached, running session) but worth a separate issue.


## Summary of Changes

Fixed `debug_view_hierarchy` bounded walk against macOS SwiftUI hierarchies. The original diagnosis (NSMutableString accumulator + IPC return cost) turned out to be downstream of two more fundamental problems uncovered by direct LLDB testing against a minimal SwiftUI app:

1. **The bounded-walk expression was failing to compile, not running slowly.** Recent LLDBs silently promote `expr -l objc` to Objective-C++ ("Expression evaluation in pure Objective-C not supported. Ran expression as 'Objective C++'"). In that mode, variadic ObjC method selectors like `appendFormat:` need Foundation in scope to parse beyond a single argument — without `@import Foundation;`, compilation fails with "too many arguments to method call, expected 1, have N". The bounded walk has been silently broken on this LLDB version; the "hang" was xc-debug waiting for a prompt that never came after a compile failure.

2. **The expression was too long to send through LLDB's PTY in raw mode.** Even with imports fixed, the ~2 KB expression ran in 5 s via batch `lldb -p`, but never even started via `xc-debug`'s PTY-backed session — the bytes arrived but lldb never began evaluation. Workaround: write the `expr` command to a temp `.lldb` script and use `command source`, so the PTY only carries the short `command source ...` line.

### Code changes
- `Sources/Core/LLDBRunner.swift`
  - `boundedTraversalExpr`: prepend `@import Darwin; @import Foundation; @import AppKit;` (Darwin brings `<stdio.h>` for `FILE`/`fopen`/`fputs`/`fclose`).
  - New file-streaming variant (`outputPath` arg): per-node lines are formatted as small NSMutableStrings and written to a host-readable `/tmp/xcmcp-vh-<pid>.txt` via libc `fputs`. The expression returns only a tiny status string; the host reads the dump from disk. Avoids both the growing-NSMutableString cost and the IPC return-value cost for very large hierarchies.
  - `viewHierarchy`: on macOS bounded walks, generate the output path, remove any stale file, and read the dump from disk after the expression returns. When the expression command exceeds 512 bytes, route it through a temp `command source` script instead of the direct PTY write.

### Verification
Tested end-to-end against a minimal SwiftUI app (`ScrollView` of 100 rows + `NSTextView` wrapped via `NSViewRepresentable`) through the `xc-debug` MCP server over JSON-RPC:

- Before this fix: `debug_view_hierarchy` with `max_depth: 4` timed out after 60+ s with no output file written.
- After this fix: same call returned in 5 s with the full 11-node hierarchy:
  ```
  <…AppKitWindowHostingView…: 0x…> frame=(0.0, 0.0, 900.0, 632.0)
    <…HostingScrollView.PlatformContainer: 0x…> frame=(66.0, 82.0, 768.0, 326.0)
      …
    <…AppKitPlatformViewHost…TextViewWrapper…: 0x…> frame=(66.0, 416.0, 768.0, 200.0)
      <NSScrollView: 0x…> frame=(0.0, 0.0, 768.0, 200.0)
        <NSClipView: 0x…> frame=(0.0, 0.0, 751.0, 200.0)
          <NSTextView: 0x…> frame=(0.0, 0.0, 751.0, 714.0)
        <NSScroller: 0x…> …
  ```

### Out of scope (follow-up worth filing)
- The crash-warning helper flags any `stopped with signal SIG*` as a crash, including `SIGSTOP` from a fresh `process attach --pid N`. After a successful bounded-walk-on-attached-running-target call, subsequent calls against a *freshly attached* process see "Process is stopped due to a crash (SIGSTOP)" — `withProcessStopped` only resumes the target if *it* was the one that interrupted it. Not exercised by the original repro (Thesis launches the app under LLDB and `view_hierarchy` is called against the same already-attached, running session) but worth a separate issue.
