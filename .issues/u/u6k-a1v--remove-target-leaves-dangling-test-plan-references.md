---
# u6k-a1v
title: remove_target leaves dangling test-plan references and crashes the server mid-call
status: completed
type: bug
priority: high
created_at: 2026-06-28T19:13:52Z
updated_at: 2026-06-28T19:22:18Z
sync:
    github:
        issue_number: "402"
        synced_at: "2026-06-28T19:23:39Z"
---

## Hard invariant (NON-NEGOTIABLE)

No mutating xc-mcp operation may EVER leave the project in a state that does not load. Full stop. The only on-disk states observable after any tool call are:
1. exactly as it was before the call, or
2. fully valid AND loadable by Xcode.

There is no third state. This must be enforced structurally for every mutating tool, not patched bug-by-bug. An agent must not be able to break the project no matter the operation, the order of operations, or a crash mid-call.

## Enforcement mechanism that makes it impossible

Every mutating operation MUST:

1. **Snapshot first.** Before changing anything, snapshot every file the operation could touch: the project file, ALL `.xctestplan` files, and ALL `.xcscheme` files.
2. **Apply to a staging copy**, never in place.
3. **Validate by actually loading the whole project graph**, not just checking that the project file is a valid plist. Run `xcodebuild -list` (and/or fully parse every scheme + test plan and resolve that every referenced target/file still exists). This is the step that catches dangling cross-file references a plist check misses.
4. **Commit only on success**, atomically (temp + rename) across all touched files together.
5. **Auto-rollback on ANY failure** — validation failure, exception, or the worker process crashing — restoring all snapshots. A crash must leave the originals untouched because nothing was swapped in until validation passed.

If the operation cannot be completed while keeping the project loadable, it MUST fail closed with a clear error and change nothing.

## Defect 1 — remove_target left dangling test-plan references, killing the project

`remove_target AdminAppTests` deleted the target from the project file but left references to it in the separate `.xctestplan` files: `Periphery.xctestplan` still listed `AdminAppTests`, and `Administration`/`Local Only` still listed `ThesisAdminTests`. A test plan pointing at a target that no longer exists makes the project fail to load. The project was dead the instant that removal completed.

A removing operation must keep the WHOLE project consistent: either cascade the removal to every `.xctestplan` and scheme that references the target, or fail closed listing the references that block it. The load-the-project validation gate above is what guarantees this generically.

## Defect 2 — remove_target crashed the server mid-call

Multiple `remove_target` calls returned `MCP error -32000: Connection closed` — the server died mid-operation, repeatedly. The integrity safeguard left the file valid, but the crash still aborts the operation and tears down the connection. A tool failure must surface as a normal error result, and per the invariant a mid-call crash must leave the project exactly as it was.

## Acceptance criteria

- For EVERY mutating tool: after the call the project either is byte-identical to before or loads cleanly via `xcodebuild -list`. Verified by a test that injects a crash and an invalid-result at each step.
- Removing a target referenced by N test plans/schemes either cascades the cleanup everywhere or refuses with an error naming them; the project loads cleanly in both cases.
- After a successful removal there are zero dangling references anywhere: project file, every `.xctestplan`, every `.xcscheme`.
- `remove_target` completes without crashing the server across repeated invocations.
- Validation gate loads the full project graph (targets + test plans + schemes), not just project-file plist validity.

## Summary of Changes

Reworked `remove_target` (RemoveTargetTool) so removing a target keeps the whole project consistent, not just the project file, and can never trap the server.

### Defect 1 — dangling test-plan / scheme references (cascade)
After removing the target in-memory, the tool now cascades the removal to disk *before* writing the project file:
- Every `.xctestplan` under the project directory that lists the target has the entry stripped (`TestPlanFile`).
- Every `.xcscheme` (shared + user) that references the target has the owning wrapper element removed via new `Core/SchemeTargetEditor` — raw-XML editing, not an XcodeProj `XCScheme` model round-trip (a round-trip silently drops elements XcodeProj doesn't model, e.g. a TestAction StoreKit reference).
- Ordering is deliberate: test plans + schemes are edited first, then the project file drops the target, so no intermediate on-disk state ever points at a missing target.
- **Post-op cross-file validation**: after the write, it re-scans every test plan and scheme and fails if any dangling reference to the target remains — validation now covers cross-file reference consistency, not just project-file plist validity.
- The success message reports exactly which test plans and schemes were edited.

### Defect 2 — server crash mid-call
Unlike RemoveAppExtensionTool, RemoveTargetTool never removed the `PBXBuildFile`s that embed/link the target's product in *other* targets' build phases. A build file left pointing at the deleted product trips a force-unwrap in XcodeProj's serializer (same class as the documented `sortProjectReferences` workaround), trapping the process — which tore down the MCP connection (`-32000: Connection closed`). The tool now removes every build file referencing the product from all build phases (and sweeps orphans) before serializing, so the write is total and surfaces failures as normal error results.

### Tests
Added 4 tests (10 total pass): cascade to test plans, cascade to schemes, no-crash when product is embedded in another target, plus existing coverage.

Files: `Sources/Core/SchemeTargetEditor.swift` (new), `Sources/Tools/Project/RemoveTargetTool.swift`, `Tests/RemoveTargetToolTests.swift`.
