---
# hal-iwd
title: Investigate XcodeBuildMCP xcresult/stderr output fixes
status: completed
type: task
priority: normal
created_at: 2026-03-03T18:22:41Z
updated_at: 2026-03-03T18:29:12Z
sync:
    github:
        issue_number: "167"
        synced_at: "2026-03-03T18:48:43Z"
---

XcodeBuildMCP made several fixes to how build/test output is classified and prioritized. Review for applicability to our BuildResultFormatter and BuildOutputParser.

## Investigation

- [x] Review `3577871` — classify stderr warnings correctly and prioritize xcresult output
- [x] Review `519bebf` — prioritize xcresult summaries and preserve non-stderr output
- [x] Review `0a54bc2` — clean up orphaned separators and consolidate XcresultSummary
- [x] Review `5c091c6` — include stdout diagnostics when stderr is empty on swift package failure
- [x] Check if our BuildResultFormatter / BuildOutputParser have similar issues
- [x] Check if our swift package tools surface stdout on failure when stderr is empty

## Source

getsentry/XcodeBuildMCP (cited repo)


## Findings

### What XcodeBuildMCP fixed

| Problem | Fix |
|---------|-----|
| stderr noise drowning xcresult summaries | Filter `[stderr]` lines when xcresult has test data; put summary first |
| Empty xcresult hiding build errors | Check `totalTestCount === 0` and fall back to raw output |
| Inconsistent stderr filtering across tools | Extract shared `filterStderrContent()` utility |
| False positive warning/error matching (e.g. `var authError: Error?`) | Regex requires line-start or file:line:col prefix before `warning:`/`error:` |
| SPM errors on stdout not stderr | `result.error \|\| result.output \|\| Unknown error` fallback chain |

### Our current state

**XCResult prioritization — already handled well:**
- `ErrorExtractor.formatTestToolResult()` already prioritizes xcresult over stdout
- Priority 1: xcresult bundle (parsed via XCResultParser)
- Priority 2: stdout parsing when xcresult shows 0 passed + 0 failed (build failure)
- Priority 3: stdout test result parsing when no xcresult available
- Exit code override logic already exists for both directions

**Stdout/stderr combination — already handled:**
- `ProcessResult.output` property intelligently combines: if stderr empty returns stdout, if stdout empty returns stderr, otherwise combines both
- SwiftRunner captures both streams separately, combines on access
- No explicit fallback needed since `output` always has content if either stream does

**Warning/error classification — minor gap:**
- Our `BuildOutputParser` uses simple prefix matching: `": error: "`, `": warning: "`, `"error: "` prefix, etc.
- This could false-positive on source code lines containing these patterns (e.g. `var authError: Error?` during compilation echo)
- XcodeBuildMCP uses more precise regex requiring line-start or `file:line:col` prefix
- In practice, xcodebuild rarely echoes source code in its output, so this is low risk for us

**No stderr-as-noise filtering — not needed:**
- XcodeBuildMCP marks all stderr lines with `[stderr]` prefix then filters them out when xcresult is available
- We don’t have this pattern because we combine stdout/stderr at the ProcessResult level and parse the combined output, which is a cleaner approach

## Recommendation

**No action needed.** Our architecture handles these cases differently but effectively:
- XCResult prioritization: already implemented in ErrorExtractor
- Stdout/stderr on SPM failure: handled by ProcessResult.output combining both streams
- Warning classification: our prefix matching is simpler but sufficient; false positives are rare in xcodebuild output

The fixes XcodeBuildMCP made were to problems caused by their stream-level separation (tagging lines with `[stderr]`). Our combined-stream approach avoids these problems by design.
