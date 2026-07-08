---
# e19-0s5
title: 'Refactor BuildOutput: dedup JSON parsing, migrate to Codable, extract scanner helpers'
status: completed
type: task
priority: normal
created_at: 2026-07-08T15:19:49Z
updated_at: 2026-07-08T15:34:05Z
sync:
    github:
        issue_number: "412"
        synced_at: "2026-07-08T15:43:48Z"
---

From /swift review of Sources/Core/BuildOutput/:
- HIGH: BuildSettingExtractor JSON parse duplicated 3x -> extract shared helper
- HIGH: Replace JSONSerialization + [String:Any] with Codable across CoverageParser + BuildSettingExtractor (7 sites)
- MED: BuildOutputParser error/warning parse + dedup repetition -> helpers
- MED: PreviewExtractor scanner/brace-balance duplication -> helpers
- MED: CoverageParser:167 force-unwrap fix
- LOW: typed throws consistency, Set membership in ErrorExtraction, BuildResultFormatter reserveCapacity/pluralize, toNode rename

## Summary of Changes

Implemented all findings from the /swift review of Sources/Core/BuildOutput/:

- **BuildSettingExtractor**: replaced 3x duplicated JSONSerialization [[String:Any]] parsing with a private Codable SettingsEntry + shared jsonSetting() helper; extractBundleId/extractAppPath now reuse it (extractAppPath also gained a JSON fast-path).
- **CoverageParser**: migrated all JSONSerialization/[String:Any] parsing to Codable models (XccovReport/SPMReport/XccovFunction); parseTargetCoverage/parseXcodebuildFormat/parseSPMFormat/parseFunctionCoverageJSON now decode from Data. Fixed the newestDate! force-unwrap. Updated 3 test call sites to pass Data.
- **BuildOutputParser**: extracted appendErrorIfNew/appendWarningIfNew helpers (mirrors existing appendLinkerErrorIfNew), collapsing 3 duplicated dedup blocks.
- **PreviewExtractor**: extracted skipCommentOrString() helper replacing the string/comment-skip triad at 4 sites; cached #Preview keyword as a static constant.
- **BuildResultFormatter**: added pluralized() helper (5 call sites), reserveCapacity in 5 detail formatters.
- **ErrorExtraction**: availableTargets now a Set (O(1) membership vs O(n^2) scan).
- **SampleOutputParser**: renamed local toNode -> node(at:).

Skipped (with rationale): typed-throws for validateMacOSSupport/formatTestToolResult (upstream showBuildSettings uses untyped throws — can't tighten across the boundary); BuildOutputParser file:line parse-block extraction (regression risk on core parser outweighs low payoff).

Full test suite: 1455 passed, 0 failed. sm format + lint clean (only pre-existing acronym warnings remain).
