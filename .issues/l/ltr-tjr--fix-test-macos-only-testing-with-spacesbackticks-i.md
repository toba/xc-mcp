---
# ltr-tjr
title: Fix test_macos only_testing with spaces/backticks in Swift Testing display names
status: completed
type: bug
priority: normal
created_at: 2026-03-09T01:07:59Z
updated_at: 2026-03-09T02:12:34Z
sync:
    github:
        issue_number: "199"
        synced_at: "2026-03-09T02:13:43Z"
---

xcodebuild's `-only-testing:` expects Swift function identifiers, not Swift Testing display names. When an LLM passes display names with spaces (e.g. "NSTextView shifts cursor when text inserted before cursor"), no tests match and the tool errors.

## Tasks
- [x] Auto-normalize identifiers with spaces: wrap method in backticks and append `()`
- [x] Update schema description to document backtick format for Swift Testing names
- [x] Pass through already-backtick-wrapped identifiers unchanged


## Summary of Changes

Auto-normalize `only_testing`/`skip_testing` identifiers containing spaces by wrapping the method component in backticks and appending `()` — matching xcodebuild's expected format for Swift Testing backtick-escaped function names. Updated schema descriptions and zero-match error messages to document the correct format.
