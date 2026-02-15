---
# xc-mcp-uew1
title: 'xcsift: Review coverage scanner optimization (60d75b54, Dec 28)'
status: completed
type: task
priority: low
created_at: 2026-02-07T17:46:40Z
updated_at: 2026-02-07T18:00:38Z
---

Performance optimization for directory scanning in upstream Sources/CoverageParser.swift. Compare against our Sources/Core/CoverageParser.swift.

## TODO

- [x] Diff upstream 60d75b54 against our CoverageParser.swift
- [x] Evaluate if optimization is relevant to our usage
- [x] Port if beneficial — not needed, already present

## Summary of Changes

No code changes needed. Both optimizations from upstream commit 60d75b54 (switching `for case let` to `while let` + `enumerator.skipDescendants()` in `findXCResultBundles` and `findTestBinary`) are already present in our `Sources/Core/CoverageParser.swift`. Our code was either adapted from a later point in xcsift history or independently applied the same improvements.
