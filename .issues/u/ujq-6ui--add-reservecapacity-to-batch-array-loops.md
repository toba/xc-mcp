---
# ujq-6ui
title: Add reserveCapacity to batch array loops
status: completed
type: task
priority: low
created_at: 2026-02-19T20:12:59Z
updated_at: 2026-02-19T20:22:57Z
sync:
    github:
        issue_number: "87"
        synced_at: "2026-02-19T20:42:41Z"
---

Arrays grown via append in loops where final size is known.

- [ ] XCStringsParser.swift:107 — results.reserveCapacity(paths.count)
- [ ] XCStringsParser.swift:135 — files.reserveCapacity(paths.count)
- [ ] XCStringsParser.swift:156 — files.reserveCapacity(paths.count)
- [ ] XCStringsWriter.swift:120 — errors.reserveCapacity(entries.count)
- [ ] XCStringsWriter.swift:143 — errors.reserveCapacity(entries.count)
- [ ] Verify tests pass
