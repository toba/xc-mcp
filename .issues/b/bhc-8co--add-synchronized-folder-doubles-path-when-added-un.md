---
# bhc-8co
title: add_synchronized_folder doubles path when added under a group with a path attribute
status: completed
type: bug
priority: normal
created_at: 2026-05-28T18:14:39Z
updated_at: 2026-05-28T18:24:32Z
sync:
    github:
        issue_number: "360"
        synced_at: "2026-05-28T18:25:12Z"
---

## Problem

`mcp__xc-project__add_synchronized_folder` stores the `folder_path` argument verbatim into the synchronized folder's `path` attribute in pbxproj, instead of trimming the parent group's path prefix. This produces a doubled on-disk path that doesn't match the convention Apple/Xcode follow when you create a target through the Xcode UI.

## Reproduction

Start with:
```
- Sync                  (PBXGroup, path = Sync)
```

Run:
```
mcp__xc-project__add_synchronized_folder(
  project_path: "Foo.xcodeproj",
  folder_path: "Sync/Sources",          // path from project root
  group_name: "Sync",
  target_name: "Sync",
)
```

Result (`list_groups` shows the display path):
```
- Sync
  - Sync/Sync/Sources   (file system synchronized)
```

In pbxproj:
```
8D3A78196115FD72B003C41B /* Sources */ = {
    isa = PBXFileSystemSynchronizedRootGroup;
    name = Sources;
    path = Sync/Sources;            // ← should be just "Sources"
    sourceTree = "<group>";
};
```

## Expected

Match what Xcode emits when you create a target via the IDE under a group whose path equals the leading component(s) of the folder argument — strip the redundant prefix:

```
8D3A78196115FD72B003C41B /* Sources */ = {
    isa = PBXFileSystemSynchronizedRootGroup;
    path = Sources;                  // ← relative to parent group
    sourceTree = "<group>";
};
```

Result of `list_groups`:
```
- Sync
  - Sync/Sources       (file system synchronized)
```

## Why it matters

Without trimming, the synchronized folder's effective resolved path becomes `<project_root>/Sync/Sync/Sources` — which doesn't exist on disk. Xcode may still find the on-disk files via some fallback, but the navigator shows a confusing doubled hierarchy (`Sync > Sync/Sources`) and the pbxproj diverges from the convention every other group in the project follows (`Core/Sources` has `path = Sources`, not `Core/Sources`).

This was hit while restructuring `Models` and `Sync` to match `Core`'s pattern in the Thesis app — see zsc-vv7 (which proposes scaffolding fixes) and the comment thread on r9i-xv0 in github.com/jsonleeapple/thesis. Agent was forced to either edit pbxproj by hand (blocked by jig nope hook) or leave the project with the wrong nesting.

## Proposed fix

When `group_name` is provided and the resolved path of that group is a prefix of `folder_path`, trim the prefix before storing — so the stored `path` attribute is relative to its parent group, consistent with what Xcode emits via the IDE.

Trimming rule (rough):
1. Resolve parent group's project-root path (walk up its `path` attributes for sourceTree `"<group>"`).
2. If `folder_path` starts with that path + "/", store the remainder. Otherwise store `folder_path` as-is.
3. Set `name` attribute only if the trimmed path's last component differs from the desired display name (rare).

Same fix probably applies to `add_file` and any other tool that stores a project-relative path under a parent group.

## Workaround for users today

None via xc-mcp alone — has to edit pbxproj by hand, which violates the project's agent-deny rules in many setups.



## Summary of Changes

- `add_synchronized_folder` no longer relies on XcodeProj's `fullPath(sourceRoot:)` (which silently returns nil when parent references aren't wired or sourceTrees aren't `.group`). Instead it walks the group hierarchy manually, accumulating `path` attributes for `.group`-sourceTree ancestors, and trims that prefix from `folder_path` before storing it on the `PBXFileSystemSynchronizedRootGroup`.
- Result matches what Xcode emits via the IDE: under a parent group with `path = Sync`, a folder at `Sync/Sources` now gets stored as `path = Sources` rather than the doubled `Sync/Sources`.
- Tests: added three new `AddFolderToolTests` covering (a) the reported bug (parent with both name and path), (b) parent with path only, and (c) parent with name only (virtual group, must keep full path).
