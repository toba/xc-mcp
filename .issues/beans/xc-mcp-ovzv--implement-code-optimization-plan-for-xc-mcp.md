---
# xc-mcp-ovzv
title: Implement code optimization plan for xc-mcp
status: completed
type: task
priority: normal
created_at: 2026-01-21T06:36:26Z
updated_at: 2026-01-21T06:44:15Z
---

Implement the 6-phase optimization plan to reduce code duplication (~900+ lines), add generics, and improve concurrency.

## Checklist
- [x] Phase 1: Create unified ProcessResult type and update runners
- [x] Phase 2: Create argument extraction helpers
- [x] Phase 3: Add session parameter resolution methods to SessionManager
- [x] Phase 4: Create shared error extraction helper
- [x] Phase 5: Parallelize DoctorTool diagnostic checks
- [x] Phase 6: Add SessionManager batch getter
- [x] Verify build succeeds
- [x] Run tests to ensure all pass

## Summary of Changes

### New Files Created
- `Sources/Utilities/ProcessResult.swift` - Unified process result type with type aliases
- `Sources/Utilities/ArgumentExtraction.swift` - Generic argument extraction helpers
- `Sources/Utilities/ErrorExtraction.swift` - Shared build error extraction

### Modified Files
- 5 runner files: Removed duplicate Result structs (~150 lines saved)
- `Sources/Server/SessionManager.swift`: Added `SessionDefaults` struct, batch getter, and resolution methods
- `Sources/Tools/Utility/DoctorTool.swift`: Parallelized diagnostic checks with async let
- 20+ tool files: Updated to use new argument extraction and session resolution helpers

### Lines Saved (Estimated)
- ProcessResult unification: ~150 lines
- Argument extraction helpers: ~300+ lines across updated tools
- Session resolution helpers: ~150+ lines across updated tools
- Error extraction: ~50 lines

Total: ~650+ lines saved with infrastructure in place for more