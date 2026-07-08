---
# t8x-j3m
title: Surface failing link target (in target 'X') on linker errors
status: ready
type: feature
priority: normal
created_at: 2026-07-08T15:41:24Z
updated_at: 2026-07-08T15:41:24Z
sync:
    github:
        issue_number: "415"
        synced_at: "2026-07-08T15:43:48Z"
---

Follow-up deferred from fm2-cax (linker-error category fix).

## Context

fm2-cax fixed the linker-error parser to preserve ld's diagnostic category (undefined vs duplicate symbol) and capture the defining files. Its third ask was left unaddressed: surface WHICH target failed to link.

Real ld failures are preceded by an xcodebuild command line like:

    Ld /…/Build/Products/Release/GoogleDocs.app/Contents/MacOS/GoogleDocs normal (in target 'GoogleDocs' from project 'Thesis')

The linker-error output currently drops this, so an agent sees the symbol/files but not the target that failed to link.

## Ask

- Track the current link target as parser state: on a line matching 'Ld … (in target ''X'' from project ''…'')', capture X.
- Add an optional target (or linkTarget) field to LinkerError (Sources/Core/BuildOutput/BuildOutputModels.swift) and stamp it on emitted undefined/duplicate errors.
- Have BuildResultFormatter.formatLinkerErrors append the target when present, e.g. '… (in target ''GoogleDocs'')'.

## Notes / considerations

- Reset the tracked target between link steps so a stale target isn't attributed to a later error.
- The Ld line may not immediately precede the ld error (intervening warnings), and parallel builds interleave output — the association is best-effort. Only stamp when confident.
- Add tests: a duplicate-symbol block preceded by an 'Ld … (in target ''X'')' line asserts target == X and the formatter includes it.

## Relevant files

- Sources/Core/BuildOutput/BuildOutputParser.swift (parseLinkerLine, linker parsing state)
- Sources/Core/BuildOutput/BuildOutputModels.swift (LinkerError)
- Sources/Core/BuildOutput/BuildResultFormatter.swift (formatLinkerErrors)
- Tests/LinkerErrorTests.swift
