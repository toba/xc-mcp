---
# ot0-wxw
title: Deduplicate batch parseEntries in XCStrings tools
status: completed
type: task
priority: normal
created_at: 2026-02-19T20:13:00Z
updated_at: 2026-02-19T20:26:22Z
---

Nearly identical parseEntries() methods in:
- XCStringsBatchAddTranslationsTool.swift:76-103
- XCStringsBatchUpdateTranslationsTool.swift:77-100

- [ ] Extract shared parseEntries function
- [ ] Update both tools to use it
- [ ] Verify tests pass
