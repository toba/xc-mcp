# ENABLE_DEBUG_DYLIB (Xcode 16+)

Moves all app code into a `.debug.dylib`, replacing the executable with a stub loader.
Default YES for Debug builds. Enables faster incremental builds and modern SwiftUI preview
execution mode.

## Known Issues

- **Code signature failures**: When the app entry point is in a Swift package with no Swift
  files in the main target, `.debug.dylib` may not generate/sign properly.
  Workaround: add empty Swift struct to main target, or set `ENABLE_DEBUG_DYLIB=NO`.
- **dSYM conflicts (Firebase Crashlytics)**: dSYM files don't upload correctly with this
  enabled. Setting NO fixes Crashlytics but disables modern previews.
- **Injected target crashes**: The `.debug.dylib` references framework symbols via rpaths
  that don't exist for injected targets. Only `ENABLE_DEBUG_DYLIB=NO` fixes this —
  `SWIFT_COMPILATION_MODE=wholemodule` has no effect.

## Sources

- [Apple Forums: Code signature not valid (thread/764503)](https://developer.apple.com/forums/thread/764503)
- [Apple Forums: Linker changes in Xcode 16 (thread/760543)](https://developer.apple.com/forums/thread/760543)
- [Firebase iOS SDK #13543](https://github.com/firebase/firebase-ios-sdk/issues/13543)
- [Firebase iOS SDK #13202](https://github.com/firebase/firebase-ios-sdk/issues/13202)
- [Apple Docs: Understanding build product layout changes](https://developer.apple.com/documentation/xcode/understanding-build-product-layout-changes)
