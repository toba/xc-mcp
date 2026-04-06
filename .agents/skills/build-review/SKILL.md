---
name: build-review
description: >
  Diagnose and resolve Xcode build system issues when programmatically creating or modifying
  Xcode project files via XcodeProj. Use when: (1) working on PreviewCaptureTool.swift or any
  code that injects targets into .xcodeproj files, (2) debugging xcodebuild failures for
  injected/preview host targets, (3) encountering linker errors like undefined symbols,
  missing dylibs, or empty framework bundles, (4) investigating .debug.dylib crashes or
  _relinkableLibraryClasses errors, (5) dealing with mergeable library issues or SPM
  transitive dependency linking failures, (6) user mentions "preview capture build",
  "inject target", or "xcodebuild linker error".
---

# Build Review

Build system knowledge for programmatically injecting targets into Xcode projects via XcodeProj.

## Required Build Settings for Injected Targets

```
Configuration:                       Debug (NOT Release — Release is broken in Xcode 26)
ENABLE_DEBUG_DYLIB:                  NO   (prevents .debug.dylib stub crash)
MERGED_BINARY_TYPE:                  none (prevents empty framework bundles)
MERGEABLE_LIBRARY:                   NO   (forces standalone dylibs, not merge stubs)
ENABLE_PREVIEWS:                     NO
SKIP_MERGEABLE_LIBRARY_BUNDLE_HOOK:  YES  (skips _relinkableLibraryClasses synthesis)
SWIFT_COMPILATION_MODE:              wholemodule (avoids incremental dependency issues)
SWIFT_OPTIMIZATION_LEVEL:            -Onone (keeps debug info, avoids compiler crashes)
SWIFT_USE_INTEGRATED_DRIVER:         YES  (default; NO causes @response file errors)
```

**Why Debug, not Release**: Release produces `Undefined symbol '_relinkableLibraryClasses'` with
no workaround in Xcode 26 (ld_classic removed). Debug builds don't merge frameworks, so
framework dylibs remain real binaries.

**Why ENABLE_DEBUG_DYLIB=NO**: The `.debug.dylib` references dependency framework symbols via
rpaths that don't exist for injected targets. `wholemodule` mode does NOT prevent this —
only this setting does.

**Why MERGED_BINARY_TYPE=none**: Prevents the linker from entering the merge codepath.
Without it, `MERGEABLE_LIBRARY=YES` frameworks produce empty stub bundles.

## SPM Static Library Transitive Linking

SPM packages built as static `.o` files get linked into consuming frameworks. When those
frameworks are mergeable/empty, the static library symbols are lost. Explicitly add
`packageProductDependencies` to the injected target from both the source target and its
transitive framework dependencies.

## Merge-Only Framework Targets

Some framework targets have SPM dependencies (e.g. HTTPTypes, ZIPFoundation) but NO
Frameworks build phase linking them. These can't produce standalone dylibs — they're
designed for merge-only linking into the app binary.

**Identifying merge-only frameworks**: A framework is merge-only if:
1. It references SPM package symbols in its source (e.g. `import HTTPTypes`)
2. Its Frameworks build phase has no files (doesn't link the SPM deps into itself)
3. The app target merges everything via `MERGED_BINARY_TYPE=automatic`

**Impact**: No build setting override (`MERGED_BINARY_TYPE=none`, `MERGEABLE_LIBRARY=NO`,
`MAKE_MERGEABLE=YES`) will produce a standalone dylib for these. Even deleting the empty
framework bundle + intermediates and rebuilding produces the same empty result.

**Solution**: Parse `import` statements from source files being compiled. Only link
framework deps whose modules are actually imported. This avoids pulling in merge-only
frameworks that the preview doesn't need.

| Framework Pattern | Standalone? | Why |
|------------------|-------------|-----|
| Has Frameworks build phase linking SPM deps | YES | Links deps into its own dylib |
| No external SPM deps | YES | Self-contained, no external symbols needed |
| Uses SPM deps but no Frameworks build phase | NO | External symbols unresolved at link time |

## macOS App Bundle Framework Embedding

macOS .app bundles use `Contents/Frameworks/` (not `Frameworks/` like iOS). When embedding
frameworks post-build:
1. Check for `Contents/` directory to detect macOS layout
2. Copy `.framework` bundles from build products into the correct Frameworks/ path
3. **Re-sign the entire .app bundle** with `codesign --force --sign - --deep`

Step 3 is required because cross-project frameworks (e.g. GRDB from a sub-xcodeproj) may
have different signing identities. Without re-signing, `dyld` rejects them at launch with
"mapping process and mapped file have different Team IDs".

## ASTMangler Infinite Recursion

The Swift compiler's ASTMangler crashes with a stack overflow when mangling types nested
inside deep closure contexts: `struct` → `var body` → `WindowGroup { }` → nested `struct`.

The recursive chain: `appendClosureComponents` → `appendAnyGenericType` → `appendType` →
`appendFunctionSignature` → `appendFunctionType` → `appendClosureComponents` (511+ frames).

**Trigger**: Preview bodies containing nested struct definitions (common pattern for
`Shape`, `View` types defined inline in `#Preview { }` blocks).

**Fix**: Place the preview body in a **top-level function** (`func _previewContent() ->
some View`) rather than inlining it in a closure nested inside a struct's computed property.
This keeps nested types at function scope (not closure-inside-struct scope), avoiding the
mangler's recursive codepath.

## Additional Constraints

- **#Preview macro stripping**: Required when compiling source files in a different target
  context. Without stripping, the `#Preview` macro in the original file can trigger the
  ASTMangler crash described above. PreviewExtractor.swift handles this with a brace-balanced
  parser that strips entire `#Preview { ... }` blocks.
- **Framework internal access**: Most views are `internal`. Options: `@testable import` or
  compile the source file directly in the preview host.
- **App target previews**: Only the single source file compiles; cross-file references fail.
- **SIP and DYLD_* variables**: macOS SIP strips `DYLD_FRAMEWORK_PATH` from signed binaries
  launched via `open -a`. Launch the binary directly instead.
- **DerivedData cache contamination**: Previous builds from other schemes (with different
  merge settings) leave stale framework products. `MERGED_BINARY_TYPE=none` as a command-line
  override doesn't force re-linking of cached frameworks. Clean empty framework stubs from
  Products/ before building to force regeneration.

## Verified Failure Modes (issue px3-c2c)

19 configurations tested:

| Config | Result |
|--------|--------|
| Release + default -O | `Undefined symbol '_relinkableLibraryClasses'` |
| Release + -Osize | Same linker error |
| Release + -Onone | .debug.dylib crash |
| Release + -Onone + wholemodule | Still generates .debug.dylib |
| Release + xcconfig OTHER_LDFLAGS -Wl,-U,... | Flag not appearing in linker args |
| Debug config (defaults) | .debug.dylib crash (Symbol not found) |
| Debug + SWIFT_SERIALIZE_DEBUGGING_OPTIONS=NO | Module dependency errors |
| Debug + SWIFT_USE_INTEGRATED_DRIVER=NO | Legacy driver can't read @response files |
| Delete .debug.dylib from bundle | Library not loaded (hard @rpath link) |
| install_name_tool + codesign | Unsealed contents in bundle root |

**Working**: Debug + `ENABLE_DEBUG_DYLIB=NO` + `MERGED_BINARY_TYPE=none` + `MERGEABLE_LIBRARY=NO`
+ import-based framework dep filtering + macOS `Contents/Frameworks/` embedding + ad-hoc re-signing

## Diagnostic Commands

```bash
# Check if framework has real binary
ls -la DerivedData/Build/Products/Debug/*.framework/

# Check for static SPM libraries
find DerivedData/Build/Products/Debug/ -name "*.o" -not -path "*/intermediates/*"

# Verify mergeable metadata
otool -l Framework.framework/Framework | grep LC_ATOM_INFO

# Check crash reports
ls ~/Library/Logs/DiagnosticReports/_PreviewHost_*.ips
```

## Reference Index

| File | Topic |
|------|-------|
| [debug-dylib.md](references/debug-dylib.md) | ENABLE_DEBUG_DYLIB mechanics, known issues, Apple forum sources |
| [mergeable-libraries.md](references/mergeable-libraries.md) | Mergeable library internals, _relinkableLibraryClasses, linker flags |
| [new-linker.md](references/new-linker.md) | ld_prime timeline, ld_classic removal, Release config dead end |
| [swift-driver.md](references/swift-driver.md) | Compilation modes, optimization levels, incremental build internals |
| [swift-syntax-preview.md](references/swift-syntax-preview.md) | Alternative #Preview extraction via swift-syntax AST |
