---
# t89-vq8
title: manage_type_identifier can't repair or remove declarations missing a UTTypeIdentifier
status: completed
type: feature
priority: normal
created_at: 2026-06-28T01:25:08Z
updated_at: 2026-06-28T01:31:17Z
sync:
    github:
        issue_number: "399"
        synced_at: "2026-06-28T01:36:58Z"
---

## Context

While configuring import/export UTIs on a target (Thesis `ThesisApp`), `list_type_identifiers` surfaced several `UTImportedTypeDeclarations` entries that have a `UTTypeDescription`, filename extensions, and MIME types but **no `UTTypeIdentifier`** (e.g. "BibTeX Document", "Research Information Systems", "Citation Style Language"). Such entries are malformed: LaunchServices ignores any type declaration lacking `UTTypeIdentifier`.

## Problem

`manage_type_identifier` addresses entries solely by `identifier` (its primary key) for add/update/remove. An entry that has no identifier therefore can't be targeted at all:
- `update` to backfill an identifier matches nothing and just appends a new entry, orphaning the malformed one
- `remove` needs an identifier to match, so the malformed entry can't be deleted

The malformed declarations are thus unmanageable through the MCP and can only be fixed by editing the pbxproj/Info.plist by hand.

## Ask

- [x] Allow targeting a type declaration by a secondary key (e.g. `UTTypeDescription`) or by index, so malformed/identifier-less entries can be updated or removed
- [x] Add a `prune`/repair action that removes declarations missing a required `UTTypeIdentifier`
- [x] Validate on `add`/`update` that required keys (`UTTypeIdentifier`) are present so the tool can't create malformed entries


## Summary of Changes

Extended `manage_type_identifier` (`Sources/Tools/Project/ManageTypeIdentifierTool.swift`) so identifier-less / malformed type declarations are manageable:

- **Secondary locators** — `update`/`remove` now accept `match_description` (by `UTTypeDescription`) or `match_index` (1-based position as shown by `list_type_identifiers`) in addition to `identifier`. Precedence: index → description → identifier.
- **Backfill / repair** — when an entry is located by description or index, an `identifier` argument is written onto it, so a declaration missing `UTTypeIdentifier` can be repaired in place instead of orphaned by a new appended entry.
- **`prune` action** — removes every declaration in the chosen list missing a (non-empty) `UTTypeIdentifier`, reporting how many and which were removed; cleanly drops the plist key when the list empties.
- **Validation** — `add` requires a non-empty `identifier`; `update` refuses to leave an entry without a `UTTypeIdentifier` and tells the caller to pass `identifier` to backfill. `identifier` removed from the schema's top-level `required` (enforced per-action).

Added 6 tests (19 total in `TypeIdentifierToolsTests`, all passing): description-backfill, remove-by-index, prune, prune-noop, and add-still-requires-identifier.
