---
# ei7-5l9
title: Add typed throws to XCStringsParser mutation methods
status: completed
type: task
priority: normal
created_at: 2026-02-19T20:12:56Z
updated_at: 2026-02-19T20:22:57Z
sync:
    github:
        issue_number: "90"
        synced_at: "2026-02-19T20:42:41Z"
---

7 XCStringsParser methods are untyped throws but only throw XCStringsError.

Methods at XCStringsParser.swift:
- [ ] updateTranslation (line 188)
- [ ] updateTranslations (line 196)
- [ ] renameKey (line 204)
- [ ] updateTranslationsBatch (line 226)
- [ ] deleteKey (line 240)
- [ ] deleteTranslation (line 247)
- [ ] deleteTranslations (line 255)
- [ ] Verify tests pass
