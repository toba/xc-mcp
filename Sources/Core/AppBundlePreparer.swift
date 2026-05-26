import Logging
import Foundation
import Subprocess

/// Prepares a debug-built macOS app bundle for launch outside Xcode.
///
/// When Xcode builds a project, framework dependencies may exist only in DerivedData's
/// `BUILT_PRODUCTS_DIR` and not be embedded in the app bundle. Xcode sets `DYLD_FRAMEWORK_PATH` at
/// launch time so the dynamic linker finds them, but that variable is stripped by SIP for
/// hardened-runtime apps launched through Launch Services ( `/usr/bin/open` ).
///
/// This utility works around the problem by:
/// 1. Symlinking non-embedded frameworks/dylibs from the build products directory into the app
///    bundle's `Contents/Frameworks/`
/// 2. Rewriting absolute `/Library/Frameworks/` install names to `@rpath/`
/// 3. Re-signing the modified bundle
public enum AppBundlePreparer {
    private static let logger = Logger(label: "AppBundlePreparer")

    /// Prepares the app bundle at `appPath` so non-embedded frameworks from `builtProductsDir` can
    /// be found at runtime.
    ///
    /// Does nothing if `builtProductsDir` is nil.
    public static func prepare(appPath: String, builtProductsDir: String?) async throws {
        guard let dir = builtProductsDir else { return }

        let fm = FileManager.default
        let frameworksDir = "\(appPath)/Contents/Frameworks"
        try fm.createDirectory(atPath: frameworksDir, withIntermediateDirectories: true)

        // Step 1: Symlink frameworks and dylibs from BUILT_PRODUCTS_DIR, then from its
        // `PackageFrameworks` subdirectory. Xcode adds both to `DYLD_FRAMEWORK_PATH` at launch, so
        // SPM package-product frameworks (which live in `PackageFrameworks/`) also need to be
        // reachable from the bundle or dyld reports "Library not loaded" at launch.
        var modified = try symlinkProducts(from: dir, into: frameworksDir)
        modified = try symlinkProducts(
            from: "\(dir)/PackageFrameworks", into: frameworksDir,
        ) || modified

        // Step 2: Rewrite absolute /Library/Frameworks/ install names to @rpath/
        let macOSDir = "\(appPath)/Contents/MacOS"

        if let macOSContents = try? fm.contentsOfDirectory(atPath: macOSDir) {
            for file in macOSContents {
                let filePath = "\(macOSDir)/\(file)"
                modified = try await rewriteAbsoluteInstallNames(at: filePath) || modified
            }
        }

        guard modified else { return }

        // Step 3: Re-sign with the original identity
        try await resignBundle(appPath: appPath)
    }

    /// Infers the build products directory from an app path inside DerivedData.
    ///
    /// If the app is at `.../Build/Products/Debug/MyApp.app` , returns `.../Build/Products/Debug` .
    /// Returns nil if the path doesn't appear to be inside DerivedData.
    public static func inferBuiltProductsDir(fromAppPath appPath: String) -> String? {
        let parent = URL(fileURLWithPath: appPath).deletingLastPathComponent().path
        // Heuristic: the app is in DerivedData if the path contains /Build/Products/
        return parent.contains("/Build/Products/")
            ? parent
            : nil
    }

    // MARK: - Private

    /// Symlinks every `.framework` and `.dylib` in `sourceDir` into `frameworksDir`, returning
    /// whether anything changed.
    ///
    /// Frameworks that are already embedded are left alone — unless they are mergeable-library
    /// reexport stubs, in which case the stub is replaced by a symlink to the full framework from
    /// `sourceDir`. Returns false (without error) if `sourceDir` does not exist.
    private static func symlinkProducts(from sourceDir: String, into frameworksDir: String) throws -> Bool {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: sourceDir, isDirectory: &isDir), isDir.boolValue else {
            return false
        }

        let contents = try fm.contentsOfDirectory(
            at: URL(fileURLWithPath: sourceDir), includingPropertiesForKeys: nil,
        )
        var modified = false

        for item in contents where item.pathExtension == "framework" {
            let destPath = "\(frameworksDir)/\(item.lastPathComponent)"
            if fm.fileExists(atPath: destPath) {
                // Already embedded. With mergeable libraries (`MERGEABLE_LIBRARY=YES` +
                // `MERGED_BINARY_TYPE=manual`), Xcode embeds a thin reexport *stub* whose symbols
                // were merged into the host binary. The stub can't satisfy the app's
                // `LC_REEXPORT_DYLIB @rpath/...` lookups, so dyld reports "Symbol missing" at
                // launch. Replace such stubs with the full framework from BUILT_PRODUCTS_DIR.
                if try isMergeableStub(embeddedFramework: destPath, fullFramework: item.path) {
                    try fm.removeItem(atPath: destPath)
                    try fm.createSymbolicLink(atPath: destPath, withDestinationPath: item.path)
                    modified = true
                }
                continue
            }
            try fm.createSymbolicLink(atPath: destPath, withDestinationPath: item.path)
            modified = true
        }

        for item in contents where item.pathExtension == "dylib" {
            let destPath = "\(frameworksDir)/\(item.lastPathComponent)"
            if fm.fileExists(atPath: destPath) { continue }
            try fm.createSymbolicLink(atPath: destPath, withDestinationPath: item.path)
            modified = true
        }

        return modified
    }

    /// Determines whether `embeddedFramework` is a mergeable-library reexport stub by comparing its
    /// binary against the full framework in `BUILT_PRODUCTS_DIR`.
    ///
    /// A merged stub is dramatically smaller than the real framework because its code and exported
    /// symbols were merged into the host binary at link time. We treat the embedded framework as a
    /// stub when its binary is less than half the size of the build-products copy. An embedded
    /// framework that Xcode copied verbatim (the non-mergeable case) is byte-identical and therefore
    /// the same size, so it is left untouched. The comparison is also idempotent: once the embedded
    /// framework has been replaced by a symlink to the full framework, both sizes match.
    static func isMergeableStub(
        embeddedFramework: String, fullFramework: String,
    ) throws -> Bool {
        guard let embeddedBinary = frameworkBinaryPath(embeddedFramework),
            let fullBinary = frameworkBinaryPath(fullFramework)
        else { return false }

        let fm = FileManager.default
        let embeddedSize = (try fm.attributesOfItem(atPath: embeddedBinary)[.size] as? Int) ?? 0
        let fullSize = (try fm.attributesOfItem(atPath: fullBinary)[.size] as? Int) ?? 0

        guard embeddedSize > 0, fullSize > 0 else { return false }

        return embeddedSize * 2 < fullSize
    }

    /// Resolves the Mach-O binary inside a `.framework` bundle, handling both versioned
    /// (`Versions/Current/Name`) and flat (`Name`) layouts. Returns nil if no binary is found.
    static func frameworkBinaryPath(_ frameworkPath: String) -> String? {
        let name = URL(fileURLWithPath: frameworkPath).deletingPathExtension().lastPathComponent
        let fm = FileManager.default
        let candidates = [
            "\(frameworkPath)/Versions/Current/\(name)",
            "\(frameworkPath)/Versions/A/\(name)",
            "\(frameworkPath)/\(name)",
        ]
        return candidates.first { fm.fileExists(atPath: $0) }
    }

    /// Rewrites absolute `/Library/Frameworks/` references to `@rpath/` .
    private static func rewriteAbsoluteInstallNames(at binaryPath: String) async throws -> Bool {
        let otoolResult = try await ProcessResult.runSubprocess(
            .path("/usr/bin/otool"),
            arguments: ["-L", binaryPath],
        )
        guard otoolResult.succeeded else { return false }

        let prefix = "/Library/Frameworks/"
        var changes: [(old: String, new: String)] = []

        for line in otoolResult.stdout.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix(prefix) {
                if let parenRange = trimmed.range(of: " (compatibility") {
                    let oldPath = String(trimmed[..<parenRange.lowerBound])
                    let newPath = "@rpath/" + String(oldPath.dropFirst(prefix.count))
                    changes.append((old: oldPath, new: newPath))
                }
            }
        }

        guard !changes.isEmpty else { return false }

        var args: [String] = []
        for change in changes { args += ["-change", change.old, change.new] }
        args.append(binaryPath)

        let installResult = try await ProcessResult.runSubprocess(
            .path("/usr/bin/install_name_tool"),
            arguments: Arguments(args),
        )

        if !installResult.succeeded {
            logger.warning("install_name_tool failed for \(binaryPath): \(installResult.stderr)")
            return false
        }

        return true
    }

    /// Re-signs the app bundle preserving the original signing identity and entitlements.
    private static func resignBundle(appPath: String) async throws {
        // Extract signing identity
        let identityResult = try await ProcessResult.runSubprocess(
            .path("/usr/bin/codesign"),
            arguments: ["-dvvv", appPath],
            mergeStderr: true,
        )

        var signingIdentity = "-"

        for line in identityResult.stdout.components(separatedBy: .newlines)
        where line.hasPrefix("Authority=") {
            signingIdentity = String(line.dropFirst("Authority=".count))
            break
        }

        // Extract entitlements
        let extractResult = try await ProcessResult.runSubprocess(
            .path("/usr/bin/codesign"),
            arguments: ["-d", "--entitlements", "-", "--xml", appPath],
        )
        var tempEntitlementsURL: URL?

        let data = Data(extractResult.stdout.utf8)
        if !data.isEmpty {
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("debug_entitlements_\(UUID().uuidString).plist")
            try data.write(to: url)
            tempEntitlementsURL = url
        }

        defer {
            if let url = tempEntitlementsURL { try? FileManager.default.removeItem(at: url) }
        }

        // Re-sign
        var signArgs = ["--force", "--sign", signingIdentity, "--deep"]
        if let url = tempEntitlementsURL { signArgs += ["--entitlements", url.path] }
        signArgs.append(appPath)

        let signResult = try await ProcessResult.runSubprocess(
            .path("/usr/bin/codesign"),
            arguments: Arguments(signArgs),
        )

        if !signResult.succeeded { logger.warning("Re-signing failed: \(signResult.stderr)") }
    }
}
