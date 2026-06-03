---
# 61e-yjo
title: Add export_archive tool to xc-build
status: completed
type: feature
priority: normal
created_at: 2026-06-03T20:32:18Z
updated_at: 2026-06-03T20:37:40Z
sync:
    github:
        issue_number: "386"
        synced_at: "2026-06-03T20:38:37Z"
---

xc-build has `mcp__xc-build__archive` to produce a signed `.xcarchive` but no companion tool to run the export step (the build-system command for `-exportArchive`). Without it, the agentic loop ends at the archive bundle and the user has to switch to Xcode Organizer or Transporter manually to produce the uploadable `.pkg` / `.ipa` and ship it.

Proposed tool: `mcp__xc-build__export_archive`.

## Parameters

- `archive_path` (required) — path to existing `.xcarchive` (matches archive tool's output).
- `export_path` (required) — directory where the exported `.pkg` / `.ipa` and `ExportOptions.plist` (effective) get written.
- `method` (required) — distribution method. Accept current Xcode 16+ values: `app-store-connect`, `release-testing`, `debugging`, `enterprise`, `developer-id`, `mac-application`. Don't accept the deprecated pre-16 spellings (`app-store`, `ad-hoc`, `development`).
- `team_id` (optional) — defaults to `DEVELOPMENT_TEAM` from project. Used in exportOptions.plist `teamID` key.
- `signing_style` (optional, default `automatic`) — `automatic` or `manual`. Most callers want automatic; if manual, also accept `provisioning_profiles` (map of bundleID → profile name).
- `destination` (optional, default `export`) — `export` or `upload`. `upload` runs the build-system export step with the upload destination so the build is delivered straight to ASC; `export` writes the artifact to disk only.
- `api_key_*` (optional, only when `destination=upload`) — `api_key_id`, `api_key_issuer_id`, `api_key_path`. Required for the upload destination per Xcode 26.
- `timeout` (optional, default 600) — same shape as archive tool.

## Internal behavior

- Synthesize `ExportOptions.plist` from the supplied parameters (don't require the caller to hand-write one). Write it inside `export_path` so the effective plist is inspectable after.
- Run the build-system export command with `-archivePath <archive_path> -exportPath <export_path> -exportOptionsPlist <synthesized.plist> -allowProvisioningUpdates`. The `-allowProvisioningUpdates` flag is essential — without it, the build system won't request missing distribution profiles (this is what trips up command-line export for projects where Xcode UI normally regenerates the profile on demand).
- On success, return path to exported `.pkg` / `.ipa` and (if applicable) the upload submission ID.
- On failure, surface the actual error from the export step (the `expected one {} but found <method>` error class is the most common one and the caller needs to see it verbatim).

## Why this matters

Hit on the Thesis project's wsh-6kg work (sibling issue): XCC's Distribute step has been unreliable for that project for unrelated reasons, and the workaround is local archive + local export + Transporter. The local archive step is covered by the new `archive` tool, but the export step has to be done either in Xcode Organizer (manual) or by spawning the underlying command directly (blocked by jig hooks in the agent context). Closing this gap turns the whole archive → export → upload pipeline into a clean agentic loop.



## Summary of Changes

Added `export_archive` tool to xc-build (and the monolithic xc-mcp server). Closes the archive → export → upload pipeline that previously dead-ended at the `.xcarchive` bundle.

**New file:** `Sources/Tools/MacOS/ExportArchiveTool.swift`

- Synthesizes `ExportOptions.plist` inside `export_path` from the supplied parameters (`method`, `team_id`, `signing_style`, `provisioning_profiles`, `destination`) so the caller never has to hand-write one. The effective plist stays on disk for post-mortem inspection.
- Validates `method` against the Xcode 16+ vocabulary (`app-store-connect`, `release-testing`, `debugging`, `enterprise`, `developer-id`, `mac-application`). The deprecated pre-16 spellings (`app-store`, `ad-hoc`, `development`) are rejected with a hint pointing at the modern equivalent.
- Runs `xcodebuild -exportArchive -archivePath -exportPath -exportOptionsPlist -allowProvisioningUpdates`. The `-allowProvisioningUpdates` flag is always passed — without it the build system won't regenerate missing distribution profiles, which is the most common command-line export failure mode.
- When `destination=upload`, also forwards `-authenticationKeyID / -authenticationKeyIssuerID / -authenticationKeyPath` for ASC delivery and requires those three parameters. Otherwise the artifacts are written to `export_path` and reported back to the caller.
- Surfaces xcodebuild's failure output verbatim on non-zero exit so the caller sees the actual error (e.g. the "expected one {} but found <method>" class of errors).

**Wired into:**
- `Sources/Servers/Build/BuildMCPServer.swift` (xc-build focused server)
- `Sources/Server/XcodeMCPServer.swift` (monolithic xc-mcp server)

Build verified via `swift build`; formatted with `sm`.
