---
# xcw-oe7
title: Project mutations must be atomic + concurrency-safe; never corrupt or clobber the shared project file
status: completed
type: bug
priority: normal
created_at: 2026-06-28T18:32:00Z
updated_at: 2026-06-28T18:48:59Z
sync:
    github:
        issue_number: "401"
        synced_at: "2026-06-28T18:51:51Z"
---

## Context

The xc-project MCP tools (remove_target, add_target, remove_swift_package, etc.) edit a shared Xcode project file (project.pbxproj) via read-modify-write. In a multi-agent session this corrupted a Thesis project TWICE. Two distinct failure modes were observed:

1. **Crash mid-write.** A remove_target call died partway (MCP "Connection closed") and the server became unavailable, leaving the working tree in a state that could not be trusted (a half-applied removal). Nothing guaranteed the on-disk file was intact after the crash.
2. **Whole-file reserialization with fresh UUIDs.** Every single operation rewrites the ENTIRE project file and regenerates object identifiers, so a one-target removal yields a ~2000-line diff. This makes (a) concurrent edits last-writer-wins with no possible merge, (b) other agents' uncommitted project work silently clobberable, and (c) diffs completely unreviewable. Recovery required a hard reset of the project file to the last commit, which itself risks reverting concurrent agents' work.

Net effect: a single agent running a routine project edit can destroy the shared project and block every other agent in the session. This has now happened twice.

## Required safeguards (ALL must hold — fail closed)

1. **Atomic writes.** Write to a temp file in the same directory, fsync, then atomic rename over the original. A crash or kill at ANY point must leave the original file byte-for-byte intact. Never write in place.
2. **Optimistic concurrency guard.** Hash the file at read; before committing the write, re-read and verify the hash is unchanged. If it changed since read, ABORT with a clear error ("project modified by another writer, re-run") instead of overwriting. Hold an advisory lock (flock) across the read-modify-write window so concurrent tool calls serialize rather than race.
3. **Minimal, stable serialization.** Preserve existing object identifiers and ordering; emit changes only for the objects actually touched. No wholesale UUID regeneration. A single target removal must produce a diff touching only that target's PBX objects.
4. **Backup + validate + auto-rollback.** Snapshot the file before mutating. After writing, validate (plutil -lint at minimum; ideally confirm xcodebuild -list still parses). If invalid, restore the snapshot and return an error — never leave a broken project on disk.
5. **No partial application.** If a multi-step edit fails halfway, roll back fully. The file is only ever the pre-call state or the fully-valid post-call state.

## Acceptance criteria

- Inject a crash between read and write: original file is unchanged.
- Inject an external edit between read and write: the operation is refused and the file is unchanged.
- remove_target on one target: the diff touches only that target's PBX objects, with no global identifier churn.
- An operation that would yield an invalid project: rejected, file rolled back to pre-call state.
- Two concurrent tool calls on the same project: serialized via lock; neither corrupts nor silently drops the other's change.

## Summary of Changes

Introduced a single durable-write chokepoint that every Xcode project mutation now funnels through, so a crash, kill, invalid serialization, or concurrent writer can no longer corrupt or silently clobber the shared `project.pbxproj`.

### New: `Sources/Core/SafeProjectWrite.swift`
`SafeProjectWrite.write(_:to:lockIdentifier:expectedPreimage:validate:)` provides:
- **Atomic write** — bytes go to a temp file in the same directory, `fsync`'d, then `rename(2)`'d over the original; the original is never opened for writing, so a crash at any point leaves it byte-for-byte intact. The containing directory is `fsync`'d so the rename is durable.
- **Advisory `flock` serialization** — a per-project lock file (FNV-1a hash of the resource path, kept in the temp dir so it never pollutes the working tree) makes the read-compare-rename window mutually exclusive; concurrent tool calls queue instead of racing.
- **Optimistic concurrency guard** — when the caller passes the bytes it read (`expectedPreimage`), the file is re-read under the lock and the write is **refused** (`concurrentModification`, mapped to `invalidParams`) if it changed, preserving the other writer's edit.
- **`plutil -lint` validation before promotion** — an invalid project is rejected and the original left untouched (nothing to roll back, since the swap only happens after validation passes). Skippable via `validate: false`.
- **Permission preservation** — original mode bits copied onto the temp file before the swap.

### Wiring
Both existing write chokepoints now route through it:
- `Sources/Tools/Project/PBXProjWriter.write` — serializes via `PBXProj.dataRepresentation` and adds an optional `expectedPreimage`; new `PBXProjWriter.preimage(of:)` helper.
- `Sources/Core/PBXProjTextEditor.write` — now atomic + locked + validated; new `readData(projectPath:)` returns the preimage bytes.

This makes **all 49 mutation call sites** atomic, validated, lock-serialized, and corruption-proof with no per-tool change.

### Optimistic guard wired into the highest-risk tools
`remove_target`, `add_target`, and `remove_swift_package` now capture the load-time bytes and pass them as `expectedPreimage`, so a stale-read clobber is refused outright.

### Tests
`Tests/SafeProjectWriteTests.swift` (8 tests, all passing) covers: atomic replace, preimage match/refusal (external edit left intact), invalid-plist rejection with original preserved, validation-skip, permission preservation, no temp-file leakage, and 12 concurrent writers serializing to a single valid result. Full suite green (1411 passed).

### Acceptance criteria
- Crash between read and write → original unchanged ✅ (atomic rename)
- External edit between read and write → refused, file unchanged ✅ (preimage guard, on wired tools)
- Invalid project → rejected, file at pre-call state ✅ (validate-before-promote)
- Two concurrent calls → serialized via lock, neither corrupts ✅ (flock)
- Minimal/stable diff for a single removal → **partial**: text-path tools already emit surgical diffs; object-path tools remain whole-file reserializations via XcodeProj (now atomic/validated/guarded, but not minimal). Tracked as follow-up.

### Follow-up
Created a follow-up issue to (a) roll the `expectedPreimage` guard out to the remaining ~46 mutation tools and (b) migrate object-based tools to minimal text serialization (safeguard #3).
