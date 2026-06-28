---
# 8a4-k7n
title: Roll optimistic-concurrency guard + minimal serialization out to all project mutation tools
status: ready
type: task
priority: normal
created_at: 2026-06-28T18:48:56Z
updated_at: 2026-06-28T18:48:56Z
sync:
    github:
        issue_number: "400"
        synced_at: "2026-06-28T18:51:51Z"
---

Follow-up to xcw-oe7, which centralized atomic/validated/locked writes through `SafeProjectWrite` and wired the optimistic `expectedPreimage` guard into the three highest-risk tools (remove_target, add_target, remove_swift_package).

Remaining work:

1. **Roll the `expectedPreimage` guard out to every remaining mutation tool.** Each tool should capture `PBXProjWriter.preimage(of:)` (object path) or `PBXProjTextEditor.readData(projectPath:)` (text path) at load and pass it to the corresponding `write(...)`. Until then, those tools are atomic + validated + lock-serialized but a stale-read clobber across a true read-modify-write race is only refused on the wired tools. ~46 object-based call sites + ~9 text-based.

2. **Minimal/stable serialization for object-based tools (safeguard #3).** `PBXProjWriter` still round-trips the whole project through XcodeProj, producing a ~2000-line diff for a one-target edit. Migrate object-based tools to the surgical `PBXProjTextEditor` path (or an equivalent) so a single mutation touches only the affected PBX objects. Large effort; do incrementally, highest-churn tools first.

Consider a shared load helper that returns `(XcodeProj, preimage)` to make (1) a one-line change per tool and reduce the chance of forgetting the guard.
