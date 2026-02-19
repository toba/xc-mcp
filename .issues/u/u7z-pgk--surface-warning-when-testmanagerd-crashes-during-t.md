---
# u7z-pgk
title: Surface warning when testmanagerd crashes during test run
status: completed
type: bug
priority: normal
created_at: 2026-02-18T06:11:55Z
updated_at: 2026-02-18T06:21:59Z
sync:
    github:
        issue_number: "77"
        synced_at: "2026-02-18T06:23:53Z"
---

The system testmanagerd process can crash (e.g. SIGSEGV pointer auth failure in HIServices) after a test run completes. xc-mcp should detect this and surface a warning so the user knows the test infrastructure had issues, even if the tests themselves passed.

## Summary of Changes

Added `detectInfrastructureWarnings()` to `ErrorExtractor` that scans stderr for testmanagerd crash indicators (SIGSEGV, SIGABRT, SIGBUS, EXC_BAD_ACCESS, pointer auth failures, lost connections, unexpected terminations) and IDETestRunnerDaemon crashes. Warnings are appended to the test result output. All three test tools now pass stderr through to the formatter. Added 8 unit tests covering the warning detection.
