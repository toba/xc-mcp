# Synchronizing package pins

Raise one package release through a set of local repositories, transitively.

## Overview

A dependent states a version floor with `from:`. A new release of the dependency stays invisible to
that dependent until somebody edits the manifest, tags a release of the dependent, and repeats the
edit one layer up. A four-deep chain costs four manual edits and four releases.

`sync_package_pins` does that walk. It reads the pins each repository declares, orders the
repositories so a dependency publishes before its dependents, then raises each floor, bumps the
member's own version, and commits, tags and pushes one layer at a time.

## The member list

The repositories come from the caller, never from a directory scan. A scan hard-codes one workspace
layout and cannot express a member that lives elsewhere.

```json
{
  "members": [
    "/Users/dev/toba-core",
    "/Users/dev/toba-hash",
    "/Users/dev/toba-data",
    "/Users/dev/jig"
  ],
  "updated": [{ "package": "toba-core", "version": "1.13.3" }],
  "bump": "minor",
  "dry_run": true
}
```

Pass the object inline, or write it to a file and name the file with `plan_path`. An inline argument
wins over the file, so a member list can live in version control while one package varies per call.

`updated` names a package that already carries a published tag. Every other member is raised
transitively.

## What the tool reads

| Source | Read from |
|---|---|
| A package member | The root `Package.swift` and every `Package.swift` one directory below it |
| An Xcode project member | The remote package references the project file holds |

The one-level walk is what picks up a benchmark suite at `<repo>/Benchmarks/Package.swift`, which
declares its own dependencies and carries its own `Package.resolved`. The walk stops at one level, so
it never descends into a build directory full of checked-out dependencies.

A member's identity is its directory name. That is what a repository URL's last path component
resolves to, so a repository cloned under a different name takes no edges in the graph.

## The order

The members form a directed graph, and the sweep publishes along it. `toba-core` publishes, then
`toba-hash` pins the new `toba-core` and publishes its own release, then `toba-data` pins both, and
so on. A dependent can only pin a version the remote already carries, so the order is a correctness
requirement rather than a presentation choice. A cycle has no such order, and the sweep refuses one.

## The all-or-nothing check

Every member is checked before any member is written. One blocked member refuses the whole run with
nothing written, because a partial run leaves the upper layers pinning tags nobody published.

A member blocks when it has a staged change, an unstaged change to a tracked file, a detached HEAD,
a branch that tracks no remote, a branch behind its remote, a commit the remote does not hold, or a
local path dependency on another repository. Untracked files do not block, because the sweep stages
by path and never picks one up.

The refusal names each blocked member and the reason. Clear them and run again.

## Versions and tags

A package member whose pins moved takes its own version bump. The sweep reads the newest release tag
the repository holds, applies the `bump` policy, and tags the commit with the result. A member listed
in `no_tag` takes the commit without the bump and the tag. An Xcode project member never takes one,
because nothing pins an application.

The sweep refuses to write when a member that needs a bump holds no release tag, or already holds the
tag the bump would create. Both checks run in the planning phase, before any write.

## Recovery

The sweep cannot undo a push. A failure partway through reports which members published, at which
version, and which did not, so the next run resumes rather than repeats. The members that already
published are unchanged by the rerun, because their floors already state the new versions.

## Limits

- Only a `from:` requirement is raised. An `exact:`, `branch:`, `revision:` or range requirement is
  reported as a note and left alone.
- An Xcode project member's resolved pins are not moved. Run `resolve_packages` afterwards.
- `dry_run` defaults to `true`. Pass `false` to write, commit, tag and push.
