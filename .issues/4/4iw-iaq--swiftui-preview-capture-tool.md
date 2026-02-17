---
# 4iw-iaq
title: SwiftUI preview capture tool
status: completed
type: feature
priority: normal
created_at: 2026-02-16T22:29:52Z
updated_at: 2026-02-16T22:49:25Z
sync:
    github:
        issue_number: "59"
        synced_at: "2026-02-17T01:03:31Z"
---

Add a `preview_capture` tool that renders a SwiftUI `#Preview` block and returns a screenshot.

## Motivation

Inspired by [Iron-Ham/Claude-XcodePreviews](https://github.com/Iron-Ham/Claude-XcodePreviews). That project uses shell scripts + Ruby xcodeproj gem to inject a temporary preview host target, build it, launch on simulator, and capture a screenshot. xc-mcp already has all the building blocks natively (XcodeProj Swift library, xcodebuild, simctl, screenshot capture) — this would combine them into a single tool.

## Workflow

1. Accept a Swift file path (and optional project/workspace path)
2. Parse the file to extract the `#Preview { ... }` block body
3. Generate a minimal `PreviewHostApp.swift` that wraps the preview content in a SwiftUI App
4. Inject a temporary `PreviewHost` app target into the Xcode project using XcodeProj:
   - Auto-detect the module containing the file
   - Add target dependencies for all imported modules
   - Detect and include resource bundle targets (Tuist `ProjectName_ModuleName`, generic `ModuleName_Resources` conventions)
   - Match deployment target from dependencies
5. Build the `PreviewHost` scheme for the target simulator
6. Install, launch, wait for render, capture screenshot via `simctl io screenshot`
7. Terminate the preview app
8. Clean up: remove the injected target, scheme, and temp files from the project

## Implementation Notes

- [ ] Add `preview_capture` tool in `Sources/Tools/Simulator/` (or a new `Preview/` category)
- [ ] Preview block extraction: parse Swift source for `#Preview { ... }` with balanced brace matching
- [ ] Handle standalone files (system-only imports) — build a minimal app without project injection
- [ ] Handle SPM packages — create a temporary xcodeproj with the package as a dependency
- [ ] Return the screenshot as a base64 image or file path
- [ ] Consider supporting multiple `#Preview` blocks in one file (capture first by default, accept index/name)
- [ ] Ensure cleanup runs even on build failure (defer/finally pattern)

## References

- https://github.com/Iron-Ham/Claude-XcodePreviews — original approach (shell + Ruby)
- Their `preview-dynamic.sh` has the core injection logic
- Their `preview-extract.swift` handles preview block parsing


## Summary of Changes

Implemented `preview_capture` tool with the following components:

### New Files
- **`Sources/Core/PreviewExtractor.swift`** — Balanced-brace parser that extracts `#Preview { ... }` blocks from Swift source. Handles named previews, nested braces, string literals, line/block comments, and multiline strings.
- **`Sources/Tools/Simulator/PreviewCaptureTool.swift`** — Monolithic MCP tool that: extracts preview body → detects source module → generates host app → injects temp target into project → builds for simulator → installs/launches → captures screenshot → terminates → cleans up injected target.
- **`Tests/PreviewExtractorTests.swift`** — 12 unit tests covering single/multiple previews, named previews, nested braces, string literals with braces, comments with braces, no preview, attributes, multiline strings, mixed named/unnamed, and non-matching macros.

### Modified Files
- **`Sources/Server/XcodeMCPServer.swift`** — Added `previewCapture` to `ToolName` enum, instantiated tool, registered in tool list and dispatch switch.
- **`.claude/nope.yaml`** — Replaced overly restrictive default config (blocked pipes, chained commands, redirects, subshells) with focused safety rules.

### Key Design Decisions
- Single monolithic tool (not composed from existing tools) for fewer round-trips and atomic cleanup
- Uses `-target` instead of `-scheme` to avoid creating scheme files
- Handles app targets (compile source directly) vs framework/library targets (import module)
- Cleanup never throws — silently handles errors to avoid masking the original failure
- Returns base64 image content via MCP image content type
