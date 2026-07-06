---
# pzg-2cv
title: No coherent way to add a StoreKit config file; add_file/remove_file corrupt scheme StoreKit references and mishandle test-target membership
status: completed
type: bug
priority: high
created_at: 2026-07-06T22:31:11Z
updated_at: 2026-07-06T22:45:56Z
sync:
    github:
        issue_number: "408"
        synced_at: "2026-07-06T23:03:04Z"
---

## Summary

There is no correct way to add a StoreKit configuration (`.storekit`) file to a project through the tools, and the generic file operations actively corrupt scheme StoreKit references. Adding/removing a `.storekit` correctly is a multi-part operation the current tools don't model.

## What a correct `.storekit` setup requires

1. A project **file reference** (so it appears in the Edit Scheme -> Run -> Options -> StoreKit Configuration picker — that picker only lists project-member `.storekit` files).
2. Membership in the **test target's resources** when tests use `SKTestSession(configurationFileNamed:)` — the config must be in the test bundle. It should **not** be in the app target's Copy Bundle Resources (a StoreKit config must not ship inside the app).
3. The scheme's Run (and often Test) action `StoreKitConfigurationFileReference` set to the correct path **relative to the scheme file** (e.g. a config at repo root, scheme under `xcshareddata/xcschemes/`, is `../../../Config.storekit`).

## Bugs observed (real session)

- **`add_file` / `remove_file` corrupted an unrelated scheme's StoreKit reference.** Removing then re-adding `Thesis.storekit` (to fix its target membership) rewrote the Standard scheme's LaunchAction `StoreKitConfigurationFileReference` from `../../../Thesis.storekit` to `../../Thesis.storekit` — wrong relative depth, silently pointing at a nonexistent path. The three sibling references were left untouched, so it was inconsistent. File operations must never mangle scheme StoreKit references; if a path is recomputed, it must be computed correctly relative to the scheme file.
- **`add_file` treats a `.storekit` as an ordinary resource** and drops it into a Copy Bundle Resources phase with no awareness that (a) it belongs in a test target for `SKTestSession`, not the shipping app, and (b) the scheme reference must be wired for it to do anything.
- **`remove_file` on a `.storekit` has silent, damaging couplings:** it drops the file from the scheme-config picker, breaks `SKTestSession(configurationFileNamed:)` tests (which `fatalError` when the config is missing from the test bundle), and leaves the scheme reference dangling/scrambled — with no warning.

## Impact

`set_scheme_storekit_config` exists and correctly writes the scheme reference in isolation, but nothing coordinates file reference + test-target membership + scheme wiring. A developer using `add_file` to add a `.storekit` ends up with it bundled into the wrong target and the scheme un-wired, so StoreKit testing silently stays disabled (`None` in the scheme). Combined with the file-op scheme corruption, this cost hours here.

## Requests

- **Fix:** `add_file`/`remove_file` (and any path-recompute logic) must never rewrite scheme StoreKit reference paths incorrectly. Ideally file ops leave scheme StoreKit references alone entirely.
- **New capability:** a dedicated `add_storekit_config` (or extend `set_scheme_storekit_config`) that does the whole job coherently: create the file reference, set membership on a named **test** target's resources (opt-in), and wire the Run/Test scheme reference with the correct relative path.
- **Guardrail:** `remove_file` on a `.storekit` should warn about the scheme-picker and `SKTestSession` couplings, or offer to unwire the scheme reference cleanly.
- Consider a `list`/`doctor` check that flags a `.storekit` in an app target's Copy Bundle Resources, or a scheme reference whose relative path doesn't resolve.

## Summary of Changes

Added a coherent StoreKit-config capability and hardened the file/scheme operations around `.storekit` files.

### New tool: `add_storekit_config`
`Sources/Tools/Project/AddStoreKitConfigTool.swift` — does the whole job in one call:
1. Creates the project **file reference** (so the config appears in Edit Scheme → Run → Options → StoreKit Configuration picker).
2. Optionally adds membership to a named **test target's** resources (`test_target`) for `SKTestSession(configurationFileNamed:)`.
3. Wires the scheme's Run/Test `StoreKitConfigurationFileReference` with the correct scheme-relative path (`target_actions`: launch/test/both).

Guardrails baked in: warns when the target isn't a unit/UI test bundle, when the config is found in an application target's Copy Bundle Resources, and when no scheme is wired (config stays inactive). Idempotent across project + scheme.

### remove_file guardrail
`RemoveFileTool` now detects `.storekit` removals: it cleanly **unwires** every scheme `StoreKitConfigurationFileReference` that resolved to the removed file (rather than leaving a dangling/scrambled reference) and warns about the scheme-picker and `SKTestSession` fatalError couplings.

### validate_scheme checks
`ValidateSchemeTool` now flags (a) a scheme StoreKit reference whose relative path doesn't resolve to a file — the exact `../../` vs `../../../` failure mode — and (b) a `.storekit` shipped in an application target's Copy Bundle Resources.

### Scheme-edit correctness
Extracted the raw-XML scheme editor from `SetSchemeStoreKitConfigTool` into a reusable `applyStoreKitReference` (+ `storeKitIdentifiers` reader) shared by all three call sites. It writes each identifier verbatim relative to the scheme file and edits actions independently, so a sibling action's path can never be recomputed to the wrong depth. Confirmed `add_file`/`remove_file` never round-trip schemes (add_file writes only pbxproj via PBXProjWriter; remove_file edits pbxproj text only). Also extracted `AddFileTool.resolveOrCreateFileReference` so file-reference creation lives in one place.

### Registration + tests
Registered `add_storekit_config` in the monolithic server, xc-project focused server, and ServerToolDirectory. Added `AddStoreKitConfigToolTests` (7) and `ValidateSchemeStoreKitTests` (3); all pass alongside existing scheme/file suites (109 related tests green).
