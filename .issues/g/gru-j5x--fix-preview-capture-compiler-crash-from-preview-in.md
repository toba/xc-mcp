---
# gru-j5x
title: 'Fix preview_capture compiler crash from #Preview in additional source files'
status: in-progress
type: bug
priority: high
created_at: 2026-02-17T02:17:40Z
updated_at: 2026-02-17T02:17:40Z
---

## Problem

When `preview_capture` processes a file owned by an app target, it compiles the source file as an additional source in the preview host target. If that file contains a `#Preview` macro, the Swift compiler crashes with infinite recursion in `ASTMangler::appendClosureComponents` (stack overflow into stack guard page).

The crash happens because the `#Preview` macro expands to nested closure/struct types, and the name mangler enters infinite recursion when mangling these in the context of a different target.

## Root Cause

In `PreviewCaptureTool.swift`, line 177:
```swift
var additionalSourcePaths: [String] = isAppTarget ? [resolvedFilePath] : []
```

The source file (which contains `#Preview`) is compiled directly into the preview host target. The preview host already has the preview body inlined in `PreviewHostApp.swift`, so the `#Preview` block in the original source file is redundant and triggers the compiler bug.

## Fix

Strip `#Preview` blocks from additional source files before compiling them, or preprocess the file to comment out / remove `#Preview` blocks. This avoids triggering the Swift compiler's ASTMangler infinite recursion.

## Tasks

- [ ] Preprocess additional source files to strip `#Preview` blocks before compilation
- [ ] Test with `Path+roundedTriangle.swift` from Thesis project
- [ ] Verify no regression on non-app-target previews
