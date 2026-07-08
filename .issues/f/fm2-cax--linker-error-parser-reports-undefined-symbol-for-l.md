---
# fm2-cax
title: Linker-error parser reports 'Undefined symbol' for ld 'duplicate symbol' errors (inverts root cause)
status: completed
type: bug
priority: normal
created_at: 2026-07-08T15:11:26Z
updated_at: 2026-07-08T15:40:19Z
sync:
    github:
        issue_number: "411"
        synced_at: "2026-07-08T15:43:48Z"
---

The build/test tools' linker-error extraction reports `Undefined symbol 'X'` when the actual ld diagnostic is `duplicate symbol 'X'`. These are OPPOSITE root causes, and the mislabel actively misdirects debugging.

## Evidence

Running `test_macos` (Standard scheme, Release) on the Thesis project, the tool surfaced:

    Linker errors:
      Undefined symbol '_relinkableLibraryClasses'

But the raw ld output in the xcactivitylog is:

    duplicate symbol '_relinkableLibraryClasses' in:
        .../Build/Products/Release/DOM.framework/Versions/A/DOM
        bundle-file
    ld: 2 duplicate symbols
    clang: error: linker command failed with exit code 1

Cost: a prior debugging session took the 'Undefined symbol' label at face value and spent a full session on a symbol-STRIPPING theory (OTHER_LDFLAGS = -no_exported_symbols removing an export). The true problem is a DUPLICATE definition (a framework linking two mergeable libraries that each emit _relinkableLibraryClasses). The label pointed 180 degrees away from the cause.

## Likely bug

The ld stderr scraper probably matches on the symbol-name pattern and hardcodes/ў defaults the category to 'Undefined symbol', or matches 'symbol' lines without distinguishing the 'duplicate symbol' vs 'Undefined symbol' / 'undefined symbol' prefixes. ld emits several distinct forms that must be preserved verbatim:
- `Undefined symbols for architecture X:` / `Undefined symbol 'X'`
- `duplicate symbol 'X' in:` (+ the two defining files) / `ld: N duplicate symbols`
- `ld: symbol(s) not found`

## Ask

- Preserve ld's own error category rather than normalizing everything to 'Undefined symbol'.
- For 'duplicate symbol', capture and surface the two (or more) defining object/framework paths that follow — they are the entire diagnosis.
- Also worth surfacing the failing link target (here: 'in target GoogleDocs') which the tool dropped.

## Summary of Changes

Root cause: the linker-error *formatter* hardcoded `Undefined symbol '<X>'` for any LinkerError with a non-empty symbol, and the *parser* only collected duplicate-symbol defining-file lines ending in .o/.a — so ld's framework-binary and `bundle-file` paths were dropped, leaving `conflictingFiles` empty and the error indistinguishable from an undefined symbol.

Fixes:
- **Model** (BuildOutputModels): added `LinkerError.Kind { undefinedSymbol, duplicateSymbol, other }` set per init, so the diagnosis category is carried explicitly instead of inferred from whether files happened to be captured.
- **Formatter** (BuildResultFormatter): labels by `kind` — 'Duplicate symbol' vs 'Undefined symbol' — and lists the defining files as '— defined in: …'.
- **Parser** (BuildOutputParser):
  - Collects every indented, non-empty line under a `duplicate symbol 'X' in:` header (frameworks, dylibs, `bundle-file`, .o/.a), not just .o/.a.
  - Flushes the pending duplicate on each new `duplicate symbol` header (previously a second header overwrote the first, losing all but the last), at the `ld: N duplicate symbols` summary, and at end-of-parse (truncated output).
  - Dedup key now includes `kind` so an undefined and a duplicate with the same symbol name stay distinct.
- **Tests** (LinkerErrorTests): 3 new tests — the exact fm2-cax framework+bundle-file shape (asserts it is NOT mislabeled Undefined), multiple duplicate symbols, and undefined-vs-duplicate-same-name distinctness.

Full Linker|BuildOutput|BuildResult|ErrorExtract|Snapshot suite: 122 passed, 0 failed.

## Deferred
The third ask — surfacing the failing link target (e.g. 'in target GoogleDocs') — is not implemented. It requires tracking the current `Ld … (in target 'X' …)` command line as parser state and threading a `target` field through LinkerError/formatter. Lower diagnostic value than the category+files fix (the conflicting framework paths already identify the culprit), and it's a self-contained follow-up. Recommend a separate issue if wanted.
