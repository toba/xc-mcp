---
# xc-mcp-sxvi
title: 'xcstrings-crud: Review BatchWriteResult fix (f8a8bda9, Jan 25)'
status: completed
type: bug
priority: normal
created_at: 2026-02-07T17:46:40Z
updated_at: 2026-02-07T18:01:27Z
---

Upstream added a boolean success flag and omits empty arrays from BatchWriteResult. Our implementation uses succeeded: Int — check if the upstream fix addresses a real issue.

## TODO

- [x] Review upstream f8a8bda9 diff
- [x] Compare upstream BatchWriteResult with our implementation
- [x] Determine if our approach has the same bug or a different design
- [x] Port fix or document why our approach differs — not porting

## Summary of Changes

No code changes needed. The upstream fix (f8a8bda9) added a `success: Bool` flag and custom encoder to omit empty arrays from `BatchWriteResult`. Our implementation uses `succeeded: Int` (a count) instead of upstream's `succeeded: [String]` (full key list), which was the main source of payload bloat. Our simpler two-field struct (`succeeded: Int`, `errors: [BatchWriteError]`) is already more token-efficient than upstream's five-field version. Our save-gate (`if result.succeeded > 0`) is also better — upstream always saves even on total failure.
