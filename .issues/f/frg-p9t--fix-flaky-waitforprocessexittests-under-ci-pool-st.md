---
# frg-p9t
title: Fix flaky WaitForProcessExitTests under CI pool starvation
status: completed
type: bug
priority: normal
created_at: 2026-07-13T16:15:42Z
updated_at: 2026-07-13T16:16:49Z
sync:
    github:
        issue_number: "427"
        synced_at: "2026-07-13T16:17:45Z"
---

Two tests in WaitForProcessExitTests.swift fail intermittently in CI (run 304, 301, 300) due to cooperative thread pool starvation during the full 1502-test parallel run:

- 'Detects process killed by SIGKILL mid-wait' (line 66): the kill fires from a cooperative-pool Task that can be starved past the 15s wait timeout, so the process is never killed and waitForProcessExit correctly returns false.
- 'Timeout is bounded' (line 86): the elapsed<15s upper bound measures wall-clock around the await, which includes unbounded continuation-scheduling latency after the kqueue wait resumes (measured 19.68s).

Fix: kill from a detached thread (immune to pool starvation); drop the fragile wall-clock upper bound (a real hang blocks forever and is caught by the CI job timeout).
