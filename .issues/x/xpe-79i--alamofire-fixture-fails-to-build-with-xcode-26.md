---
# xpe-79i
title: Alamofire fixture fails to build with Xcode 26
status: completed
type: bug
priority: high
created_at: 2026-02-18T02:05:12Z
updated_at: 2026-02-18T02:41:49Z
---

The pinned Alamofire 5.11.1 (f73a2fcb) doesn't compile with the current Swift toolchain (Xcode 26). Errors:
- `cannot assign to value: 'error' is a 'let' constant` in DataRequest, DataStreamRequest, DownloadRequest
- `converting non-escaping value to '@Sendable (Progress) -> Void' may allow it to escape` in Request.swift

5.11.1 is the latest release — no upstream fix available yet. Options:
1. Pin to a fork/branch with fixes
2. Skip Alamofire integration tests until upstream ships a compatible release
3. Apply local patches in fetch-fixtures.sh

Affects: `build_Alamofire_iOS`, `build_Alamofire_macOS` integration tests.

## Summary of Changes

Fixed Alamofire patches in `scripts/fetch-fixtures.sh` to use exact per-file python string replacements matching the actual clean-clone file format. All three files (DataRequest, DataStreamRequest, DownloadRequest) have the same single-line format with `self.error` already present. The patch renames `error` binding to `validationError` and adds `@escaping` to ProgressHandler closures.
