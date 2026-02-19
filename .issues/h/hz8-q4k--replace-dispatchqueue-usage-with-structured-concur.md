---
# hz8-q4k
title: Replace DispatchQueue usage with structured concurrency
status: completed
type: task
priority: normal
created_at: 2026-02-19T20:12:57Z
updated_at: 2026-02-19T20:26:22Z
---

Replace remaining DispatchQueue calls with Swift concurrency primitives.

- [ ] LLDBRunner.swift:228 — asyncAfter → Task.sleep(for:)
- [ ] LLDBRunner.swift:329-330 — DispatchQueue.global().async → structured Task
- [ ] StartDeviceLogCapTool.swift:122 — DispatchQueue.global().async → Task
- [ ] Verify tests pass
