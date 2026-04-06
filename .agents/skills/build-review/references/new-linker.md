# The New Linker (ld_prime) — Xcode 15+

## Timeline

1. **ld** — original
2. **ld64 / ld_classic** — rewrite ~2005
3. **ld_prime / ld_new** — Xcode 15 default

- **Xcode 15**: ld_prime default; `-ld_classic` available as fallback
- **Xcode 16**: ld_classic **deprecated**
- **Xcode 26**: ld_classic **removed** — no fallback

## Release Config Is a Dead End (Xcode 26)

Release builds produce `Undefined symbol: _relinkableLibraryClasses`. This symbol is
synthesized by the linker only during actual framework merges — see
[mergeable-libraries.md](mergeable-libraries.md) for the full mechanism.

No workaround exists in Xcode 26:
- `-ld_classic` — removed
- `-dead_strip -allow_dead_duplicates` — doesn't resolve this symbol
- `-Wl,-U,_relinkableLibraryClasses` — clobbered by other flags in multi-target builds
- `SWIFT_ENABLE_LIBRARY_EVOLUTION=NO` — no effect
- Sanitizer settings — no effect

**Use Debug configuration for injected targets.**

## Sources

- [Apple Forums: Xcode 26 Link Error (thread/788064)](https://developer.apple.com/forums/thread/788064)
- [Apple Forums thread/733317](https://developer.apple.com/forums/thread/733317)
- [Apple Forums thread/731089](https://developer.apple.com/forums/thread/731089)
- [Swift Forums: Flags for linker with MERGED_BINARY_TYPE](https://forums.swift.org/t/flags-for-linker-compilator-when-using-merged-binary-type/71864)
