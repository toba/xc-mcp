---
# gqs-ket
title: Auto-create workspace-scoped xcresult bundles for test tools
status: completed
type: feature
priority: normal
created_at: 2026-05-07T16:47:00Z
updated_at: 2026-05-07T16:55:46Z
sync:
    github:
        issue_number: "312"
        synced_at: "2026-05-07T17:06:07Z"
---

Port concept from XcodeBuildMCP PR #401 (commit 01609ca7a9bffec05092f372d6aa6f8900d4c47c in getsentry/XcodeBuildMCP).

When callers don't provide a result bundle path to test tools, create a workspace-scoped one automatically. Makes xcresult artifacts consistently available in text and structured output. Extend workspace cleanup so managed result bundles are pruned safely without touching user-created bundles.

## Tasks

- [x] Decide on workspace-scoped storage location (under DerivedData or a dedicated xc-mcp scratch dir)
- [x] Generate a default -resultBundlePath when caller omits one (simulator, device, macOS test commands)
- [x] Preserve explicit user-provided paths as-is
- [x] Add cleanup that prunes managed bundles only (ownership marker or path prefix check)
- [x] Tests for: managed cleanup, user-bundle preservation, default path surfaces in result

## Reference

- Upstream PR: https://github.com/getsentry/XcodeBuildMCP/pull/401
- Pairs well with the xcresult bundle path surfacing feature (sibling issue)



## Summary of Changes

Replaced the previous `\$TMPDIR/xc-mcp-test-<UUID>.xcresult` + immediate-defer-delete behavior with a persistent, project-scoped cache that mirrors `DerivedDataScoper`.

- New `Sources/Core/TestResultBundleScoper.swift` — places auto-generated bundles under `~/Library/Caches/xc-mcp/TestResults/<ProjectName>-<hash>/<UUID>.xcresult`. Project hash uses the same SHA-256-prefix convention as `DerivedDataScoper` so callers see consistent project identifiers across both caches.
- Opportunistic 7-day retention prune runs each time a new path is generated, scoped to `.xcresult` entries only so an unrelated file in a misconfigured base dir is never touched.
- Env overrides: `XC_MCP_TEST_RESULTS_PATH=<absolute>` to force a base directory (CI), `XC_MCP_DISABLE_TEST_RESULTS_SCOPING=1` to revert to the unmanaged `\$TMPDIR` fallback.
- `Sources/Core/TestToolHelper.swift`: now requests a managed path from the scoper instead of the inline tmp helper. The `isTemporaryBundle` ownership flag and the three `defer`/`catch` cleanup blocks were deleted — both managed and user-supplied bundles now persist, which is the required precondition for the sibling feature `ubg-9z1` (surface bundle path).
- User-supplied paths are still passed through untouched and never managed by the scoper.
- Tests in `Tests/TestResultBundleScoperTests.swift` cover: scoped-dir stability across runs, divergence across project paths, workspace-precedence, env overrides, retention pruning (old removed, fresh kept, unrelated files left alone), nil paths, and the disable flag falling back to tmp.
