---
# wqm-jx7
title: Fix preview_capture end-to-end rendering
status: in-progress
type: task
priority: normal
created_at: 2026-02-16T23:44:27Z
updated_at: 2026-02-17T00:15:16Z
---

preview_capture tool is implemented (PreviewExtractor, PreviewCaptureTool, registration, 334 tests pass) but has never successfully rendered a preview screenshot end-to-end. Three problems discovered during testing against thesis project:

1. iOS Simulator build falls back to macOS ("Unable to find a destination") even though iphonesimulator26.2 SDK is installed
2. macOS fallback path crashes at launch (debug dylib can't resolve framework symbols) and screencapture window ID lookup fails
3. All thesis previews use internal types from dependency frameworks, so no preview body compiles in isolation

## Steps

- [ ] Create a simple public-only test preview file in thesis DOM target
- [ ] Fix iOS Simulator destination matching (SDKROOT, deployment target)
- [ ] Revert framework targets to `import Module` approach (not direct source compilation)
- [ ] End-to-end test: build on iOS Sim → simctl install → launch → screenshot → cleanup
- [ ] Clean up test file, verify project.pbxproj is clean, document known limitations

## Known Limitations (to document)

- Framework targets: only previews using public types work
- App targets: only fully self-contained previews (no cross-file deps) work
- macOS-only projects: window capture unreliable (future work)

## Key Files

- `Sources/Tools/Simulator/PreviewCaptureTool.swift`
- `Sources/Core/PreviewExtractor.swift`


## Progress (Session 2026-02-16)

### Code Changes Made (in Sources/Tools/Simulator/PreviewCaptureTool.swift)

1. **Framework targets use `import ModuleName`** instead of compiling source directly
   - `generateHostSource()` now accepts `moduleName` param, emits `import ModuleName` for framework targets
   - `additionalSourcePaths` is empty for framework targets (source NOT compiled into host)
   - `injectTarget()` links the source framework itself + transitive deps for framework targets

2. **iOS Sim destination fixes** (partial - blocked by missing iOS Simulator platform)
   - Passes `SDKROOT=iphoneos SUPPORTED_PLATFORMS=iphoneos iphonesimulator` as xcodebuild command-line overrides for iOS Sim builds
   - Passes `SDKROOT=macosx SUPPORTED_PLATFORMS=macosx` for macOS fallback builds
   - `findBuiltAppPath()` also passes the same SDK overrides so BUILT_PRODUCTS_DIR matches
   - Broader fallback detection: checks for "Unable to find a destination", "no matching destination", "does not support destination"
   - Added stderr logging for iOS Sim failures before fallback

3. **macOS window capture replaced with ScreenCaptureKit**
   - Removed `findWindowID()` (CGWindowList approach) and `screencapture -l` subprocess
   - Added `captureMacOSWindow(bundleId:)` using SCShareableContent + SCScreenshotManager (same approach as ScreenshotMacWindowTool)
   - Added `ensureGUIConnection()` for WindowServer access
   - Imports: added `AppKit`, `ScreenCaptureKit`

4. **Build configuration forced to Release**
   - Debug builds generate `.debug.dylib` and `__preview.dylib` that crash on launch (unresolved symbols from dependency frameworks)
   - Preview host always builds with `-configuration Release GCC_OPTIMIZATION_LEVEL=0 ENABLE_PREVIEWS=NO`

5. **SUPPORTED_PLATFORMS default** set to `iphoneos iphonesimulator macosx` when source target doesn't have it explicitly (project-level inheritance issue)

### Test Preview File Created
- `/Users/jason/Developer/toba/thesis/DOM/Sources/TestPreview.swift`
- Self-contained `#Preview` using only SwiftUI types (no custom types)
- No `public struct` (avoids "cannot use protocol 'View' in a public conformance" when SwiftUI isn't publicly exported by the module)

### Blocking Issue: macOS app crashes on launch

**Root cause**: Even in Release mode, the preview host binary references `_$s4Core10DiagnosticCN` (Core.Diagnostic type metadata) and crashes with `Symbol not found`. The symbol is referenced from AND expected in the main binary itself — not from a framework.

**Key finding**: `Core.framework` IS embedded in `Contents/Frameworks/` but `nm Core.framework/Core | grep DiagnosticCN` returns empty — the symbol is NOT exported from Core.framework. It's an internal symbol that somehow got pulled into the preview host's link.

**Theory**: When linking DOM.framework (which depends on Core), the linker resolves some symbols from Core into the host binary, but `Core.Diagnostic` (an internal class) isn't available because it's not exported. The `import DOM` in the host source pulls in DOM's module interface which transitively references Core types.

### Possible Fixes (not yet tried)
1. **Use `@testable import DOM`** — would make internal types visible but requires `ENABLE_TESTABILITY=YES` in the source target's build config
2. **Investigate why Core.Diagnostic is referenced** — may be pulled in via DOM's .swiftmodule metadata; could be a Swift compiler bug or expected behavior for transitive deps
3. **Try `DEAD_CODE_STRIPPING=YES`** — might strip the unreferenced Core.Diagnostic metadata
4. **Link Core.framework explicitly** — the embed phase has it, but maybe the linker isn't finding it at link time
5. **Try `LD_RUNPATH_SEARCH_PATHS` additions** — current value includes `@executable_path/Frameworks` and `@executable_path/../Frameworks` which should work for macOS .app bundles

### Environment Issues
- **iOS Simulator platform NOT installed** in Xcode 26.2 — `xcodebuild` says "iOS 26.2 is not installed" for ALL iOS Sim destinations
- User had iOS 26.1 runtime but removed it; iOS 18.5 runtime also doesn't work with Xcode 26 SDK
- Need to install iOS Simulator platform via Xcode > Settings > Components (or `xcodebuild -downloadPlatform iOS`)
- ALL simulators are currently shut down

### Test Harness
- `/tmp/test-preview-simple.sh` — sends set_session_defaults then preview_capture via JSON-RPC
- Server launched with `xc-mcp /Users/jason/Developer/toba/thesis` (base path argument)
- Simulator UDID: `2F218323-8C02-4BD1-BD2B-C7AE781574CB` (iPhone 16 Pro, iOS 18.5 — currently non-functional)

### swift build: PASSES (334 tests pass)
### swift test: PASSES (334 tests pass)
