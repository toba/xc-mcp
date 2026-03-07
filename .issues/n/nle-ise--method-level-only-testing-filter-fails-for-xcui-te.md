---
# nle-ise
title: method-level only_testing filter fails for XCUI test targets
status: ready
type: bug
priority: normal
tags:
    - bug
created_at: 2026-03-07T21:38:25Z
updated_at: 2026-03-07T21:38:25Z
sync:
    github:
        issue_number: "181"
        synced_at: "2026-03-07T21:39:58Z"
---

## Problem

`only_testing` with a full method path doesn't match XCUI tests:

```
only_testing: ["TestAppUITests/TypingPerformanceTests/testRapidTypingSignpostDuration"]
→ "No tests matched the only_testing filter"
```

But class-level filtering works:
```
only_testing: ["TestAppUITests/TypingPerformanceTests"]
→ Tests passed (1 passed)
```

This may be an xcodebuild quirk with UI test bundles, or a formatting issue with how the filter is passed.

## Investigation

- [ ] Check if xcodebuild requires different identifier format for XCUI tests
- [ ] Test with raw xcodebuild to isolate whether it's an xc-mcp issue or xcodebuild behavior
