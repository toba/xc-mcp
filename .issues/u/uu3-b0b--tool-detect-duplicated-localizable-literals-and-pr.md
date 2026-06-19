---
# uu3-b0b
title: 'Tool: detect duplicated localizable literals and promote to reusable String Catalog keys'
status: completed
type: feature
priority: normal
created_at: 2026-06-19T21:24:49Z
updated_at: 2026-06-19T21:40:54Z
sync:
    github:
        issue_number: "392"
        synced_at: "2026-06-19T21:44:15Z"
---

## Motivation

Reviewing a SwiftUI app (Thesis) for localized strings re-typed as bare literals at multiple independent call sites is slow and error-prone by hand. The String Catalog (`.xcstrings`) already merges *identical* source literals into one entry, but identical literals scattered across many files still risk drift (a reworded variant silently forks into a second translation) and lack a single, type-safe edit point.

Xcode 26 auto-generates a camelCased Swift symbol from a manual `SCREAMING_SNAKE` catalog key (e.g. key `ADD_CITATION_TO_GROUP` -> `Text(.addCitationToGroup(ordinal:))`, `RENAME` -> `Button(.rename)`). Promoting a duplicated literal to such a key gives one source of truth + compiler-checked uses. Doing this discovery + migration manually across ~25 files for a handful of strings is exactly the kind of mechanical sweep an MCP tool should own.

## Proposed tool

A `localize_duplicates` (name TBD) tool that, given a Swift target/dir + its `.xcstrings`:

1. **Scan** Swift sources for localizable string literals in the initializers that take `LocalizedStringKey`/`LocalizedStringResource`: `Text`, `Label`, `Button`, `Toggle`, `Menu`, `Picker`, `Link`, `TextField`, `NavigationLink`, `.help/.navigationTitle/.confirmationDialog/.alert/.accessibilityLabel`, plus `String(localized:)` / `LocalizedStringResource("...")` and `CustomLocalizedStringResourceConvertible` switch-case literal returns.
2. **Report** every literal that appears at 2+ *independent* call sites, with file:line for each, ranked by occurrence count.
3. **Filter the noise** that naive grep produces:
   - Exclude SF Symbol / identifier strings (e.g. `plus`, `doc.text`, `tablecells`, `text.bubble`) — args to `Image(systemName:)`, `Label(systemImage:)`, `Symbol.*`, role/tag identifiers, single-glyph separators like an en dash.
   - Recognize literals already single-sourced via a `CustomLocalizedStringResourceConvertible` extension (definition + references should not read as a dup needing promotion).
4. **Suggest** a `SCREAMING_SNAKE` key per candidate and show the generated symbol it would yield, reusing any existing key whose value already matches.
5. **Apply (optional, --write)**: add the manual key to the `.xcstrings` (`extractionState: manual`, en `stringUnit`, optional comment), then rewrite each call site literal to the generated symbol (`Button("Cancel")` -> `Button(.cancel)`), leaving `role:`/`systemImage:`/action args intact. Handle Swift-keyword keys (e.g. `IMPORT` -> backticked `.`import``) safely or warn.

## Validation example (from Thesis)

Sweep surfaced `"Cancel"` hand-typed in 15 files / 19 sites, `"Delete"` in 4, `"Save"`/`"Import"` in 3 each, `"Done"`/`"Remove"`/`"None Selected"`/`"Untitled"` in 2 each — all strong promote candidates — while correctly *excluding* field-name dups already centralized in a convertible extension and SF Symbol names. That filtering (steps 3) is the hard part a tool earns its keep on; raw grep gives a 60-line list that is mostly false positives.

## Notes

- Builds on existing `.xcstrings` handling (cf. monitored citation `Ryu0118/xcstrings-crud`).
- Read-only report mode is the MVP; `--write` migration is a fast-follow.
- Should be language-aware enough to skip string literals that are not localizable args (regex over AST/SwiftSyntax preferred over line grep to nail step 3).


## Implementation notes

Scope narrowed (per user): the tool only CREATES reusable manual catalog keys; it does not scan Swift sources to find duplicates (the LLM does that). No Swift source rewriting.

New tool `xcstrings_promote_literals`:
- Adds extractionState=manual source-language entries to the .xcstrings.
- Derives SCREAMING_SNAKE key (or accepts explicit key), reports generated camelCased symbol.
- Reuses existing key holding the same value; reports collisions.
- Supports parameterized values (format placeholders like 

symbol.
- Reuses an existing key that already holds the same value; reports collisions when a key exists with a different value.
- Supports parameterized values (format placeholders, e.g. the named form shown in the user's Xcode screenshot) and reports the generated method signature, e.g. `addCitationToGroup(ordinal: String)`. The format string is stored verbatim so Xcode parses the placeholders.

Wiring: registered in `xc-strings` server (StringsMCPServer, StringsToolName) and ServerToolDirectory. Tests in `XCStringsPromoteLiteralsToolTests.swift` (20 tests, passing).


## Summary of Changes

Delivered `xcstrings_promote_literals` — a focused, create-only tool (no source scanning, no source rewriting):

- `Sources/Core/XCStrings/LocalizableKeyNaming.swift` — SCREAMING_SNAKE key derivation, camelCased symbol generation (keyword-backticked), and format-placeholder parsing for parameterized values.
- `Sources/Core/XCStrings/XCStringsWriter.swift` — `addManualKey` (extractionState=manual, source-language stringUnit, optional comment).
- `Sources/Core/XCStrings/XCStringsParser.swift` — `promoteLiterals` (create / reuse / collision handling, single save).
- `Sources/Core/XCStrings/Models/XCStringsModels.swift` — `PromoteLiteralRequest`, `PromotedLiteral` (incl. `signature`), `PromoteLiteralsResult`.
- `Sources/Tools/XCStrings/XCStringsPromoteLiteralsTool.swift` — MCP tool.
- Registered in StringsMCPServer, StringsToolName, ServerToolDirectory.
- `Tests/XCStringsPromoteLiteralsToolTests.swift` — 20 tests (all green).
