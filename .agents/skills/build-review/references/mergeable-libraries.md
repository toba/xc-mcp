# Mergeable Libraries (Xcode 15+)

Dynamic-library semantics with near-static-library launch performance. The linker copies
mergeable library contents into the consuming binary at link time.

## Build Settings

- **`MERGEABLE_LIBRARY=YES`** (on framework targets): Makes library eligible for merging.
  Adds `LC_ATOM_INFO` metadata. Does NOT merge by itself.
- **`MERGED_BINARY_TYPE`** (on consuming targets):
  - `automatic` — merges ALL direct dynamic framework deps in the same project
  - `manual` — only merges deps with `MERGEABLE_LIBRARY=YES`
  - `none` / unset — no merging
- **`MAKE_MERGEABLE`**: Linker flag equivalent of `MERGEABLE_LIBRARY`. Do NOT pass as a manual
  build setting override — causes duplicate `_relinkableLibraryClasses` when combined with
  Xcode's automatic settings. Use `MAKE_MERGEABLE=NO` to force real dylib output.
- **`SKIP_MERGEABLE_LIBRARY_BUNDLE_HOOK=YES`**: Passes `-no_merged_libraries_hook` to linker,
  skipping `_relinkableLibraryClasses` synthesis. Breaks `Bundle(for:)` for merged classes.

## Debug vs Release

**Debug builds do NOT merge.** Frameworks keep real dylib binaries. This makes Debug safe
for injected targets.

## Empty Framework Bundles

When merging occurs, frameworks become small stubs (no real code). The bundle remains for
resource lookup via `Bundle`, but the Mach-O has no code. This is expected behavior, but
breaks any target that dynamically links against these frameworks independently.

## _relinkableLibraryClasses Internals

When the linker performs `-merge_framework`, it synthesizes these data structures:

```c
struct FrameworkLocation { const char *name; void *unknown; };
struct LibraryClass { void *isa; FrameworkLocation *location; };
extern LibraryClass relinkableLibraryClasses[];
```

A static constructor calls `objc_setHook_getImageName()` to map class ISA pointers back to
framework paths, enabling `Bundle(for:)` to return correct bundles for merged classes.

**Why undefined symbol errors occur**: The linker emits a reference to
`_relinkableLibraryClasses` when it detects `LC_ATOM_INFO` in linked frameworks, but only
synthesizes the definition during an actual merge. If the merge doesn't happen (wrong config,
injected target), the reference becomes undefined. Fix: `MERGED_BINARY_TYPE=none`.

## Linker Flags

| Flag | Effect |
|------|--------|
| `-make_mergeable` | Add `LC_ATOM_INFO` (= `MERGEABLE_LIBRARY=YES`) |
| `-merge-lFoo` | Statically merge library Foo |
| `-merge_framework Foo` | Statically merge framework Foo |
| `-no_merged_libraries_hook` | Skip `objc_setHook_getImageName` constructor |

## Sources

- [kateinoigakukun/MergeableLibraryInternals](https://github.com/kateinoigakukun/MergeableLibraryInternals)
- [WWDC23: Meet mergeable libraries](https://developer.apple.com/videos/play/wwdc2023/10268/)
- [Apple Docs: Configuring mergeable libraries](https://developer.apple.com/documentation/xcode/configuring-your-project-to-use-mergeable-libraries)
- [humancode.us: All about mergeable libraries](https://www.humancode.us/2024/01/02/all-about-mergeable-libraries.html)
- [Apple Forums thread/751167](https://developer.apple.com/forums/thread/751167)
